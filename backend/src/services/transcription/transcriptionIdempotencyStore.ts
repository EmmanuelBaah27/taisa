import Database from 'better-sqlite3';
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

type StoredStatus = 'queued' | 'provider_started' | 'completed';

interface ReceiptRow {
  idempotency_key: string;
  request_id: string;
  owner_id: string;
  audio_sha256: string;
  status: StoredStatus;
  terminal_event_encrypted: string | null;
}

export type TranscriptionIdempotencyResult =
  | { status: 'start' }
  | { status: 'ambiguous'; requestId: string }
  | { status: 'completed'; event: Record<string, unknown> };

export class TranscriptionIdempotencyConflictError extends Error {
  readonly code = 'IDEMPOTENCY_KEY_REUSED';
  constructor() { super('IDEMPOTENCY_KEY_REUSED'); }
}

export class TranscriptionRequestNotFoundError extends Error {
  readonly code = 'REQUEST_NOT_FOUND';
  constructor() { super('REQUEST_NOT_FOUND'); }
}

export class TranscriptionIdempotencyStore {
  private readonly database: Database.Database;
  private readonly encryptionKey: Buffer;

  constructor(options: { databasePath: string; encryptionKeyBase64: string }) {
    this.encryptionKey = Buffer.from(options.encryptionKeyBase64, 'base64');
    if (this.encryptionKey.length !== 32
      || this.encryptionKey.toString('base64') !== options.encryptionKeyBase64) {
      throw new Error('Transcription receipt encryption key must be exactly 32 base64-encoded bytes');
    }
    this.database = new Database(options.databasePath);
    this.database.pragma('journal_mode = WAL');
    this.database.pragma('busy_timeout = 5000');
    this.database.exec(`
      CREATE TABLE IF NOT EXISTS transcription_idempotency_receipts (
        idempotency_key TEXT PRIMARY KEY,
        request_id TEXT NOT NULL UNIQUE,
        owner_id TEXT NOT NULL,
        audio_sha256 TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('queued', 'provider_started', 'completed')),
        terminal_event_encrypted TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_transcription_idempotency_request
        ON transcription_idempotency_receipts(request_id, owner_id);
    `);
  }

  begin(input: {
    key: string; requestId: string; ownerId: string; audioSHA256: string;
  }): TranscriptionIdempotencyResult {
    return this.database.transaction(() => {
      const existing = this.database.prepare(`
        SELECT * FROM transcription_idempotency_receipts
        WHERE idempotency_key = ? OR request_id = ?
      `).get(input.key, input.requestId) as ReceiptRow | undefined;
      if (existing) {
        if (existing.idempotency_key !== input.key
          || existing.request_id !== input.requestId
          || existing.owner_id !== input.ownerId
          || existing.audio_sha256 !== input.audioSHA256) {
          throw new TranscriptionIdempotencyConflictError();
        }
        return this.result(existing);
      }
      const now = new Date().toISOString();
      this.database.prepare(`
        INSERT INTO transcription_idempotency_receipts (
          idempotency_key, request_id, owner_id, audio_sha256, status, created_at, updated_at
        ) VALUES (?, ?, ?, ?, 'queued', ?, ?)
      `).run(input.key, input.requestId, input.ownerId, input.audioSHA256, now, now);
      return { status: 'start' } as const;
    }).immediate();
  }

  markProviderStarted(key: string): void {
    const result = this.database.prepare(`
      UPDATE transcription_idempotency_receipts
      SET status = 'provider_started', updated_at = ?
      WHERE idempotency_key = ? AND status = 'queued'
    `).run(new Date().toISOString(), key);
    if (result.changes !== 1) throw new Error('IDEMPOTENCY_STATE_CONFLICT');
  }

  complete(key: string, event: Record<string, unknown>): void {
    const result = this.database.prepare(`
      UPDATE transcription_idempotency_receipts
      SET status = 'completed', terminal_event_encrypted = ?, updated_at = ?
      WHERE idempotency_key = ? AND status = 'provider_started'
    `).run(this.encrypt(event), new Date().toISOString(), key);
    if (result.changes !== 1) throw new Error('IDEMPOTENCY_STATE_CONFLICT');
  }

  reconcile(
    requestId: string,
    ownerId: string,
  ): TranscriptionIdempotencyResult | { status: 'missing'; requestId: string } {
    const row = this.database.prepare(`
      SELECT * FROM transcription_idempotency_receipts
      WHERE request_id = ? AND owner_id = ?
    `).get(requestId, ownerId) as ReceiptRow | undefined;
    return row ? this.result(row) : { status: 'missing', requestId };
  }

  authorizeRetry(requestId: string, ownerId: string): { status: 'authorized'; requestId: string } {
    return this.database.transaction(() => {
      const row = this.database.prepare(`
        SELECT status FROM transcription_idempotency_receipts
        WHERE request_id = ? AND owner_id = ?
      `).get(requestId, ownerId) as { status: StoredStatus } | undefined;
      if (!row) throw new TranscriptionRequestNotFoundError();
      if (row.status !== 'provider_started') throw new Error('IDEMPOTENCY_STATE_CONFLICT');
      const result = this.database.prepare(`
        UPDATE transcription_idempotency_receipts
        SET status = 'queued', updated_at = ?
        WHERE request_id = ? AND owner_id = ? AND status = 'provider_started'
      `).run(new Date().toISOString(), requestId, ownerId);
      if (result.changes !== 1) throw new Error('IDEMPOTENCY_STATE_CONFLICT');
      return { status: 'authorized', requestId } as const;
    }).immediate();
  }

  close(): void { this.database.close(); }

  private result(row: ReceiptRow): TranscriptionIdempotencyResult {
    switch (row.status) {
      case 'queued': return { status: 'start' };
      case 'provider_started': return { status: 'ambiguous', requestId: row.request_id };
      case 'completed':
        if (!row.terminal_event_encrypted) throw new Error('INVALID_IDEMPOTENCY_RECORD');
        return { status: 'completed', event: this.decrypt(row.terminal_event_encrypted) };
    }
  }

  private encrypt(value: Record<string, unknown>): string {
    const nonce = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.encryptionKey, nonce);
    const ciphertext = Buffer.concat([
      cipher.update(JSON.stringify(value), 'utf8'), cipher.final(),
    ]);
    return JSON.stringify({
      version: 1,
      nonce: nonce.toString('base64'),
      tag: cipher.getAuthTag().toString('base64'),
      ciphertext: ciphertext.toString('base64'),
    });
  }

  private decrypt(value: string): Record<string, unknown> {
    const envelope = JSON.parse(value) as {
      version?: unknown; nonce?: unknown; tag?: unknown; ciphertext?: unknown;
    };
    if (envelope.version !== 1 || typeof envelope.nonce !== 'string'
      || typeof envelope.tag !== 'string' || typeof envelope.ciphertext !== 'string') {
      throw new Error('INVALID_IDEMPOTENCY_RECORD');
    }
    const decipher = createDecipheriv(
      'aes-256-gcm', this.encryptionKey, Buffer.from(envelope.nonce, 'base64'),
    );
    decipher.setAuthTag(Buffer.from(envelope.tag, 'base64'));
    return JSON.parse(Buffer.concat([
      decipher.update(Buffer.from(envelope.ciphertext, 'base64')), decipher.final(),
    ]).toString('utf8')) as Record<string, unknown>;
  }
}

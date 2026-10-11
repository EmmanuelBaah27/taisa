import Database from 'better-sqlite3';
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import type { CoachingResponse } from '@taisa/shared';

type StoredStatus = 'queued' | 'provider_started' | 'completed' | 'failed';

interface IdempotencyRow {
  idempotency_key: string;
  request_id: string;
  owner_id: string | null;
  request_hash: string;
  status: StoredStatus;
  response_encrypted: string | null;
  idempotency_receipt: string | null;
  terminal_sequence: number | null;
  failure_code: string | null;
  failure_retryable: number | null;
}

export type IdempotencyResult =
  | { status: 'start' }
  | { status: 'ambiguous'; requestId: string }
  | { status: 'completed'; response: CoachingResponse; idempotencyReceipt: string; terminalSequence: number }
  | { status: 'failed'; requestId: string; code: string; retryable: boolean };

export class IdempotencyConflictError extends Error {
  readonly code = 'IDEMPOTENCY_KEY_REUSED';
  constructor() { super('IDEMPOTENCY_KEY_REUSED'); }
}

export class CoachingRequestNotFoundError extends Error {
  readonly code = 'REQUEST_NOT_FOUND';
  constructor() { super('REQUEST_NOT_FOUND'); }
}

export class CoachingIdempotencyStore {
  private readonly database: Database.Database;
  private readonly encryptionKey: Buffer;

  constructor(options: { databasePath: string; encryptionKeyBase64: string }) {
    this.encryptionKey = Buffer.from(options.encryptionKeyBase64, 'base64');
    if (this.encryptionKey.length !== 32 || this.encryptionKey.toString('base64') !== options.encryptionKeyBase64) {
      throw new Error('Coaching receipt encryption key must be exactly 32 base64-encoded bytes');
    }
    this.database = new Database(options.databasePath);
    this.database.pragma('journal_mode = WAL');
    this.database.pragma('busy_timeout = 5000');
    this.database.exec(`
      CREATE TABLE IF NOT EXISTS coaching_idempotency_receipts (
        idempotency_key TEXT PRIMARY KEY,
        request_id TEXT NOT NULL UNIQUE,
        owner_id TEXT NOT NULL,
        request_hash TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('queued', 'provider_started', 'completed', 'failed')),
        response_encrypted TEXT,
        idempotency_receipt TEXT,
        terminal_sequence INTEGER,
        failure_code TEXT,
        failure_retryable INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_coaching_idempotency_request
        ON coaching_idempotency_receipts(request_id);
    `);
    const columns = this.database.prepare(
      'PRAGMA table_info(coaching_idempotency_receipts)',
    ).all() as Array<{ name: string }>;
    if (!columns.some((column) => column.name === 'owner_id')) {
      this.database.exec('ALTER TABLE coaching_idempotency_receipts ADD COLUMN owner_id TEXT');
    }
  }

  begin(input: { key: string; requestId: string; requestHash: string; ownerId: string }): IdempotencyResult {
    return this.database.transaction(() => {
      const existing = this.rowForKey(input.key);
      if (existing) {
        if (existing.request_id !== input.requestId || existing.request_hash !== input.requestHash
          || existing.owner_id !== input.ownerId) {
          throw new IdempotencyConflictError();
        }
        return this.result(existing);
      }
      const now = new Date().toISOString();
      this.database.prepare(`
        INSERT INTO coaching_idempotency_receipts (
          idempotency_key, request_id, owner_id, request_hash, status, created_at, updated_at
        ) VALUES (?, ?, ?, ?, 'queued', ?, ?)
      `).run(input.key, input.requestId, input.ownerId, input.requestHash, now, now);
      return { status: 'start' } as const;
    }).immediate();
  }

  markProviderStarted(key: string): void {
    const result = this.database.prepare(`
      UPDATE coaching_idempotency_receipts
      SET status = 'provider_started', updated_at = ?
      WHERE idempotency_key = ? AND status = 'queued'
    `).run(new Date().toISOString(), key);
    if (result.changes !== 1) throw new Error('IDEMPOTENCY_STATE_CONFLICT');
  }

  complete(
    key: string,
    response: CoachingResponse,
    idempotencyReceipt: string,
    terminalSequence = 0,
  ): void {
    const result = this.database.prepare(`
      UPDATE coaching_idempotency_receipts
      SET status = 'completed', response_encrypted = ?, idempotency_receipt = ?,
        terminal_sequence = ?, updated_at = ?
      WHERE idempotency_key = ? AND status = 'provider_started'
    `).run(this.encrypt(response), idempotencyReceipt, terminalSequence, new Date().toISOString(), key);
    if (result.changes !== 1) throw new Error('IDEMPOTENCY_STATE_CONFLICT');
  }

  fail(key: string, code: string, retryable: boolean): void {
    const result = this.database.prepare(`
      UPDATE coaching_idempotency_receipts
      SET status = 'failed', failure_code = ?, failure_retryable = ?, updated_at = ?
      WHERE idempotency_key = ? AND status IN ('queued', 'provider_started')
    `).run(code, retryable ? 1 : 0, new Date().toISOString(), key);
    if (result.changes !== 1) throw new Error('IDEMPOTENCY_STATE_CONFLICT');
  }

  reconcile(requestId: string, ownerId: string): IdempotencyResult | { status: 'missing'; requestId: string } {
    const row = this.database.prepare(
      'SELECT * FROM coaching_idempotency_receipts WHERE request_id = ? AND owner_id = ?',
    ).get(requestId, ownerId) as IdempotencyRow | undefined;
    return row ? this.result(row) : { status: 'missing', requestId };
  }

  authorizeRetry(requestId: string, ownerId: string): { status: 'authorized'; requestId: string } {
    return this.database.transaction(() => {
      const row = this.database.prepare(
        'SELECT status FROM coaching_idempotency_receipts WHERE request_id = ? AND owner_id = ?',
      ).get(requestId, ownerId) as { status: StoredStatus } | undefined;
      if (!row) throw new CoachingRequestNotFoundError();
      if (row.status !== 'provider_started') throw new Error('IDEMPOTENCY_STATE_CONFLICT');
      const result = this.database.prepare(`
        UPDATE coaching_idempotency_receipts SET status = 'queued', updated_at = ?
        WHERE request_id = ? AND owner_id = ? AND status = 'provider_started'
      `).run(new Date().toISOString(), requestId, ownerId);
      if (result.changes !== 1) throw new Error('IDEMPOTENCY_STATE_CONFLICT');
      return { status: 'authorized', requestId } as const;
    }).immediate();
  }

  close(): void { this.database.close(); }

  private rowForKey(key: string): IdempotencyRow | undefined {
    return this.database.prepare(
      'SELECT * FROM coaching_idempotency_receipts WHERE idempotency_key = ?',
    ).get(key) as IdempotencyRow | undefined;
  }

  private result(row: IdempotencyRow): IdempotencyResult {
    switch (row.status) {
      case 'queued': return { status: 'start' };
      case 'provider_started': return { status: 'ambiguous', requestId: row.request_id };
      case 'completed':
        if (!row.response_encrypted || !row.idempotency_receipt || row.terminal_sequence === null) {
          throw new Error('INVALID_IDEMPOTENCY_RECORD');
        }
        return {
          status: 'completed',
          response: this.decrypt(row.response_encrypted),
          idempotencyReceipt: row.idempotency_receipt,
          terminalSequence: row.terminal_sequence,
        };
      case 'failed':
        if (!row.failure_code || row.failure_retryable === null) throw new Error('INVALID_IDEMPOTENCY_RECORD');
        return {
          status: 'failed', requestId: row.request_id,
          code: row.failure_code, retryable: row.failure_retryable === 1,
        };
    }
  }

  private encrypt(response: CoachingResponse): string {
    const nonce = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.encryptionKey, nonce);
    const ciphertext = Buffer.concat([
      cipher.update(JSON.stringify(response), 'utf8'),
      cipher.final(),
    ]);
    return JSON.stringify({
      version: 1,
      nonce: nonce.toString('base64'),
      tag: cipher.getAuthTag().toString('base64'),
      ciphertext: ciphertext.toString('base64'),
    });
  }

  private decrypt(encrypted: string): CoachingResponse {
    const envelope = JSON.parse(encrypted) as {
      version?: unknown; nonce?: unknown; tag?: unknown; ciphertext?: unknown;
    };
    if (envelope.version !== 1
      || typeof envelope.nonce !== 'string'
      || typeof envelope.tag !== 'string'
      || typeof envelope.ciphertext !== 'string') {
      throw new Error('INVALID_IDEMPOTENCY_RECORD');
    }
    const decipher = createDecipheriv(
      'aes-256-gcm', this.encryptionKey, Buffer.from(envelope.nonce, 'base64'),
    );
    decipher.setAuthTag(Buffer.from(envelope.tag, 'base64'));
    const plaintext = Buffer.concat([
      decipher.update(Buffer.from(envelope.ciphertext, 'base64')),
      decipher.final(),
    ]).toString('utf8');
    return JSON.parse(plaintext) as CoachingResponse;
  }
}

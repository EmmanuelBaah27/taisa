import { createHash, randomUUID } from 'crypto';
import Database from 'better-sqlite3';
import { encryptFeedback, parseFeedbackEncryptionKey } from './feedbackCrypto';

export interface FeedbackRepositoryOptions {
  readonly encryptionKeyBase64: string;
  readonly databasePath?: string;
  readonly now?: () => Date;
}

export interface StoreFeedbackInput {
  readonly ownerCredentialId: string;
  readonly idempotencyId: string;
  readonly consentedAt: string;
  readonly example: Readonly<Record<string, unknown>>;
}

export class FeedbackRepository {
  private readonly database: Database.Database;
  private readonly key: Buffer;
  private readonly now: () => Date;

  constructor(options: FeedbackRepositoryOptions) {
    this.key = parseFeedbackEncryptionKey(options.encryptionKeyBase64);
    this.now = options.now ?? (() => new Date());
    this.database = new Database(options.databasePath ?? ':memory:');
    this.database.pragma('journal_mode = WAL');
    this.database.pragma('busy_timeout = 5000');
    this.database.exec(`CREATE TABLE IF NOT EXISTS feedback_examples (
      receipt_id TEXT PRIMARY KEY NOT NULL,
      owner_credential_id TEXT NOT NULL,
      idempotency_id TEXT NOT NULL,
      payload_digest TEXT NOT NULL,
      nonce TEXT NOT NULL,
      authentication_tag TEXT NOT NULL,
      ciphertext TEXT NOT NULL,
      consented_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE(owner_credential_id, idempotency_id)
    )`);
  }

  store(input: StoreFeedbackInput): string {
    const serialized = JSON.stringify(input.example);
    const digest = createHash('sha256').update(serialized).digest('hex');
    const existing = this.database.prepare(`SELECT receipt_id, payload_digest
      FROM feedback_examples WHERE owner_credential_id = ? AND idempotency_id = ?`)
      .get(input.ownerCredentialId, input.idempotencyId) as
      | { receipt_id: string; payload_digest: string }
      | undefined;
    if (existing) {
      if (existing.payload_digest !== digest) throw new Error('IDEMPOTENCY_CONFLICT');
      return existing.receipt_id;
    }
    const receiptId = randomUUID();
    const envelope = encryptFeedback(serialized, this.key);
    this.database.prepare(`INSERT INTO feedback_examples
      (receipt_id, owner_credential_id, idempotency_id, payload_digest, nonce,
        authentication_tag, ciphertext, consented_at, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`)
      .run(
        receiptId,
        input.ownerCredentialId,
        input.idempotencyId,
        digest,
        envelope.nonce,
        envelope.authenticationTag,
        envelope.ciphertext,
        input.consentedAt,
        this.now().toISOString(),
      );
    return receiptId;
  }

  delete(ownerCredentialId: string, receiptId: string): boolean {
    return this.database.prepare(`DELETE FROM feedback_examples
      WHERE receipt_id = ? AND owner_credential_id = ?`).run(receiptId, ownerCredentialId).changes === 1;
  }

  count(): number {
    return (this.database.prepare('SELECT count(*) AS count FROM feedback_examples').get() as { count: number }).count;
  }

  inspectPersistedValues(): string {
    return JSON.stringify(this.database.prepare('SELECT * FROM feedback_examples').all());
  }

  close(): void {
    this.database.close();
  }
}

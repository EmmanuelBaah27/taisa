import { createHmac, randomBytes, randomUUID, timingSafeEqual } from 'crypto';
import Database from 'better-sqlite3';

export interface DeviceCredentialStoreOptions {
  databasePath?: string;
  pepper: string;
  now?: () => Date;
}
export interface IssuedDeviceCredential {
  credentialId: string;
  token: string;
}

interface CredentialRow {
  id: string;
  token_digest: string;
}

export class DeviceCredentialStore {
  private readonly database: Database.Database;
  private readonly pepper: string;
  private readonly now: () => Date;

  constructor(options: DeviceCredentialStoreOptions) {
    if (options.pepper.length < 24) throw new Error('Device credential pepper is too short');
    this.pepper = options.pepper;
    this.now = options.now ?? (() => new Date());
    this.database = new Database(options.databasePath ?? ':memory:');
    this.database.pragma('busy_timeout = 5000');
    this.database.pragma('journal_mode = WAL');
    this.database.exec(`
      CREATE TABLE IF NOT EXISTS device_enrollment_codes (
        code_digest TEXT PRIMARY KEY,
        expires_at TEXT NOT NULL,
        consumed_at TEXT
      );
      CREATE TABLE IF NOT EXISTS device_credentials (
        id TEXT PRIMARY KEY,
        token_digest TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL,
        revoked_at TEXT
      );
    `);
  }

  private digest(value: string): string {
    return createHmac('sha256', this.pepper).update(value, 'utf8').digest('hex');
  }

  registerEnrollmentCode(code: string, expiresAt: string): void {
    if (!code.trim() || !Number.isFinite(Date.parse(expiresAt))) {
      throw new Error('Invalid enrollment code configuration');
    }
    this.database.prepare(`INSERT OR IGNORE INTO device_enrollment_codes
      (code_digest, expires_at, consumed_at) VALUES (?, ?, NULL)`)
      .run(this.digest(code), expiresAt);
  }

  enroll(code: string): IssuedDeviceCredential {
    const transaction = this.database.transaction(() => {
      const codeDigest = this.digest(code);
      const row = this.database.prepare(`SELECT expires_at, consumed_at
        FROM device_enrollment_codes WHERE code_digest = ?`).get(codeDigest) as
        | { expires_at: string; consumed_at: string | null }
        | undefined;
      const now = this.now();
      if (!row || row.consumed_at !== null || Date.parse(row.expires_at) <= now.getTime()) {
        throw new Error('INVALID_ENROLLMENT_CODE');
      }
      const token = randomBytes(32).toString('base64url');
      const credentialId = randomUUID();
      const consumed = this.database.prepare(`UPDATE device_enrollment_codes
        SET consumed_at = ? WHERE code_digest = ? AND consumed_at IS NULL`)
        .run(now.toISOString(), codeDigest);
      if (consumed.changes !== 1) throw new Error('INVALID_ENROLLMENT_CODE');
      this.database.prepare(`INSERT INTO device_credentials
        (id, token_digest, created_at, revoked_at) VALUES (?, ?, ?, NULL)`)
        .run(credentialId, this.digest(token), now.toISOString());
      return { credentialId, token };
    });
    return transaction.immediate();
  }

  authenticate(token: string): string | null {
    if (!token) return null;
    const supplied = Buffer.from(this.digest(token), 'hex');
    const rows = this.database.prepare(`SELECT id, token_digest FROM device_credentials
      WHERE revoked_at IS NULL`).all() as CredentialRow[];
    for (const row of rows) {
      const stored = Buffer.from(row.token_digest, 'hex');
      if (stored.length === supplied.length && timingSafeEqual(stored, supplied)) return row.id;
    }
    return null;
  }

  revokeCredential(credentialId: string): void {
    this.database.prepare(`UPDATE device_credentials SET revoked_at = ?
      WHERE id = ? AND revoked_at IS NULL`).run(this.now().toISOString(), credentialId);
  }

  listActiveCredentialIds(): string[] {
    return (this.database.prepare(`SELECT id FROM device_credentials
      WHERE revoked_at IS NULL ORDER BY id`).all() as Array<{ id: string }>).map((row) => row.id);
  }

  inspectPersistedValues(): string {
    return JSON.stringify({
      enrollment: this.database.prepare('SELECT * FROM device_enrollment_codes').all(),
      credentials: this.database.prepare('SELECT * FROM device_credentials').all(),
    });
  }

  close(): void {
    this.database.close();
  }
}

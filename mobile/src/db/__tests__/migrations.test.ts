import {
  DatabaseRecoveryRequiredError,
  createDatabaseLifecycle,
  openDatabaseWithDependencies,
} from '../openDatabase';
import { runMigrations, UnsupportedDatabaseVersionError } from '../migrations';
import { SCHEMA_V1_STATEMENTS } from '../schema';
import type { DatabaseLike } from '../types';

class FakeDatabase implements DatabaseLike {
  readonly appliedStatements: string[] = [];
  readonly calls: string[] = [];
  userVersion: number;
  failWhenStatementIncludes: string | null = null;
  cipherVersion: string | null = '4.6.1';
  closed = false;

  private transactionSnapshot: { statementCount: number; userVersion: number } | null = null;

  constructor(userVersion: number) {
    this.userVersion = userVersion;
  }

  async execAsync(source: string): Promise<void> {
    this.calls.push(source);

    if (source === 'BEGIN IMMEDIATE') {
      this.transactionSnapshot = {
        statementCount: this.appliedStatements.length,
        userVersion: this.userVersion,
      };
      return;
    }

    if (source === 'COMMIT') {
      this.transactionSnapshot = null;
      return;
    }

    if (source === 'ROLLBACK') {
      if (this.transactionSnapshot) {
        this.appliedStatements.splice(this.transactionSnapshot.statementCount);
        this.userVersion = this.transactionSnapshot.userVersion;
      }
      this.transactionSnapshot = null;
      return;
    }

    if (this.failWhenStatementIncludes && source.includes(this.failWhenStatementIncludes)) {
      throw new Error('injected migration failure');
    }

    if (source === 'PRAGMA user_version = 1') {
      this.userVersion = 1;
      return;
    }

    this.appliedStatements.push(source);
  }

  async getFirstAsync<T>(source: string): Promise<T | null> {
    this.calls.push(source);
    if (source === 'PRAGMA user_version') {
      return { user_version: this.userVersion } as T;
    }
    if (source === 'SELECT count(*) AS count FROM sqlite_master') {
      return { count: 0 } as T;
    }
    if (source === 'PRAGMA cipher_version') {
      return this.cipherVersion === null
        ? null
        : ({ cipher_version: this.cipherVersion } as T);
    }
    return null;
  }

  async closeAsync(): Promise<void> {
    this.closed = true;
  }
}

describe('local database migrations', () => {
  test('runs schema version 1 once and advances user_version transactionally', async () => {
    const db = new FakeDatabase(0);

    await runMigrations(db);
    await runMigrations(db);

    expect(db.userVersion).toBe(1);
    expect(db.calls.filter((statement) => statement === 'BEGIN IMMEDIATE')).toHaveLength(1);
    expect(
      db.appliedStatements.filter((statement) =>
        statement.includes('CREATE TABLE conversations'),
      ),
    ).toHaveLength(1);
  });

  test('creates every local entity and both FTS5 search indexes with foreign keys', async () => {
    const db = new FakeDatabase(0);

    await runMigrations(db);

    for (const table of [
      'profile',
      'conversations',
      'messages',
      'goals',
      'milestones',
      'actions',
      'action_transitions',
      'evidence',
      'memory_items',
      'memory_sources',
      'memory_confirmations',
      'usage_receipts',
      'migration_state',
    ]) {
      expect(
        db.appliedStatements.some((statement) =>
          statement.includes(`CREATE TABLE ${table}`),
        ),
      ).toBe(true);
    }

    expect(
      db.appliedStatements.some((statement) =>
        statement.includes('CREATE VIRTUAL TABLE message_search USING fts5'),
      ),
    ).toBe(true);
    expect(
      db.appliedStatements.some((statement) =>
        statement.includes('CREATE VIRTUAL TABLE evidence_search USING fts5'),
      ),
    ).toBe(true);
    expect(
      db.appliedStatements.some((statement) => statement.includes('REFERENCES conversations(id)')),
    ).toBe(true);
  });

  test('memory confirmations are durable, source-scoped, and lifecycle constrained', () => {
    const table = SCHEMA_V1_STATEMENTS.find((statement) =>
      statement.includes('CREATE TABLE memory_confirmations'),
    );

    expect(table).toContain("status TEXT NOT NULL CHECK (status IN ('pending', 'confirmed', 'consumed'))");
    expect(table).toContain('proposal_digest TEXT NOT NULL');
    expect(table).toContain('resolution_digest TEXT');
    expect(table).toContain('local_user_action_id TEXT');
    expect(table).toContain('source_message_id TEXT NOT NULL REFERENCES messages(id)');
  });

  test('action transitions preserve content-free completion provenance', () => {
    const table = SCHEMA_V1_STATEMENTS.find((statement) =>
      statement.includes('CREATE TABLE action_transitions'),
    );

    expect(table).toContain('action_id TEXT NOT NULL REFERENCES actions(id)');
    expect(table).toContain('source_message_id TEXT NOT NULL REFERENCES messages(id)');
    expect(table).toContain("kind TEXT NOT NULL CHECK (kind = 'explicit-user-completion')");
    expect(table).toContain('from_lifecycle TEXT NOT NULL');
    expect(table).toContain('to_lifecycle TEXT NOT NULL');
  });

  test('rolls back the schema and user_version when a migration statement fails', async () => {
    const db = new FakeDatabase(0);
    db.failWhenStatementIncludes = 'CREATE TABLE messages';

    await expect(runMigrations(db)).rejects.toThrow('injected migration failure');

    expect(db.userVersion).toBe(0);
    expect(db.appliedStatements).toEqual([]);
    expect(db.calls.at(-1)).toBe('ROLLBACK');
  });

  test('refuses to open a database created by a newer app schema', async () => {
    const db = new FakeDatabase(2);

    await expect(runMigrations(db)).rejects.toBeInstanceOf(UnsupportedDatabaseVersionError);
    expect(db.calls).not.toContain('BEGIN IMMEDIATE');
  });

  test('memory sources require one source and reject duplicate links of either type', () => {
    const table = SCHEMA_V1_STATEMENTS.find((statement) =>
      statement.includes('CREATE TABLE memory_sources'),
    );

    expect(table).toContain('id TEXT PRIMARY KEY NOT NULL');
    expect(table).toContain(
      '(message_id IS NOT NULL AND evidence_id IS NULL) OR\n' +
        '      (message_id IS NULL AND evidence_id IS NOT NULL)',
    );
    expect(SCHEMA_V1_STATEMENTS).toContain(
      `CREATE UNIQUE INDEX memory_sources_message_unique
    ON memory_sources(memory_item_id, message_id)
    WHERE message_id IS NOT NULL`,
    );
    expect(SCHEMA_V1_STATEMENTS).toContain(
      `CREATE UNIQUE INDEX memory_sources_evidence_unique
    ON memory_sources(memory_item_id, evidence_id)
    WHERE evidence_id IS NOT NULL`,
    );
  });
});

describe('encrypted database opening', () => {
  const validKey = 'ab'.repeat(32);

  test.each([
    ['absent', null],
    ['empty', ''],
  ])('fails closed when SQLCipher cipher_version is %s', async (_label, cipherVersion) => {
    const db = new FakeDatabase(0);
    db.cipherVersion = cipherVersion;

    await expect(
      openDatabaseWithDependencies({
        databaseFile: { exists: async () => true },
        secureStore: {
          getItemAsync: async () => validKey,
          setItemAsync: async () => undefined,
          whenUnlockedThisDeviceOnly: 42,
        },
        crypto: { getRandomBytesAsync: async () => new Uint8Array(32) },
        sqlite: { openDatabaseAsync: async () => db },
      }),
    ).rejects.toMatchObject({
      code: 'DATABASE_CONFIGURATION_REQUIRED',
      reason: 'sqlcipher-unavailable',
    });

    expect(db.closed).toBe(true);
    expect(db.calls).toEqual([
      `PRAGMA key = "x'${validKey}'"`,
      'PRAGMA cipher_version',
    ]);
    expect(db.calls).not.toContain('BEGIN IMMEDIATE');
    expect(db.appliedStatements).toEqual([`PRAGMA key = "x'${validKey}'"`]);
  });

  test('validates a non-empty SQLCipher version before reading sqlite_master', async () => {
    const db = new FakeDatabase(1);

    await expect(
      openDatabaseWithDependencies({
        databaseFile: { exists: async () => true },
        secureStore: {
          getItemAsync: async () => validKey,
          setItemAsync: async () => undefined,
          whenUnlockedThisDeviceOnly: 42,
        },
        crypto: { getRandomBytesAsync: async () => new Uint8Array(32) },
        sqlite: { openDatabaseAsync: async () => db },
      }),
    ).resolves.toBe(db);

    expect(db.calls.indexOf('PRAGMA cipher_version')).toBeLessThan(
      db.calls.indexOf('SELECT count(*) AS count FROM sqlite_master'),
    );
    expect(db.calls).not.toContain('BEGIN IMMEDIATE');
  });

  test('fails into typed recovery when the database exists but its key is missing', async () => {
    const db = new FakeDatabase(0);
    const openDatabaseAsync = jest.fn(async () => db);
    const getRandomBytesAsync = jest.fn(async () => new Uint8Array(32));
    const setItemAsync = jest.fn(async () => undefined);

    const opening = openDatabaseWithDependencies({
      databaseFile: { exists: async () => true },
      secureStore: {
        getItemAsync: async () => null,
        setItemAsync,
        whenUnlockedThisDeviceOnly: 42,
      },
      crypto: { getRandomBytesAsync },
      sqlite: { openDatabaseAsync },
    });

    await expect(opening).rejects.toMatchObject({
      code: 'DATABASE_RECOVERY_REQUIRED',
      reason: 'missing-key',
    });
    await expect(opening).rejects.toBeInstanceOf(DatabaseRecoveryRequiredError);
    expect(getRandomBytesAsync).not.toHaveBeenCalled();
    expect(setItemAsync).not.toHaveBeenCalled();
    expect(openDatabaseAsync).not.toHaveBeenCalled();
  });

  test('preserves an existing archive when SecureStore cannot read its key', async () => {
    const openDatabaseAsync = jest.fn(async () => new FakeDatabase(0));
    const getRandomBytesAsync = jest.fn(async () => new Uint8Array(32));
    const setItemAsync = jest.fn(async () => undefined);

    await expect(
      openDatabaseWithDependencies({
        databaseFile: { exists: async () => true },
        secureStore: {
          getItemAsync: async () => {
            throw new Error('keychain unavailable');
          },
          setItemAsync,
          whenUnlockedThisDeviceOnly: 42,
        },
        crypto: { getRandomBytesAsync },
        sqlite: { openDatabaseAsync },
      }),
    ).rejects.toMatchObject({
      code: 'DATABASE_RECOVERY_REQUIRED',
      reason: 'key-store-unavailable',
    });

    expect(getRandomBytesAsync).not.toHaveBeenCalled();
    expect(setItemAsync).not.toHaveBeenCalled();
    expect(openDatabaseAsync).not.toHaveBeenCalled();
  });

  test('does not generate a new key when SecureStore reads fail for a new database', async () => {
    const openDatabaseAsync = jest.fn(async () => new FakeDatabase(0));
    const getRandomBytesAsync = jest.fn(async () => new Uint8Array(32));
    const setItemAsync = jest.fn(async () => undefined);

    await expect(
      openDatabaseWithDependencies({
        databaseFile: { exists: async () => false },
        secureStore: {
          getItemAsync: async () => {
            throw new Error('keychain unavailable');
          },
          setItemAsync,
          whenUnlockedThisDeviceOnly: 42,
        },
        crypto: { getRandomBytesAsync },
        sqlite: { openDatabaseAsync },
      }),
    ).rejects.toMatchObject({
      code: 'DATABASE_CONFIGURATION_REQUIRED',
      reason: 'secure-store-unavailable',
    });

    expect(getRandomBytesAsync).not.toHaveBeenCalled();
    expect(setItemAsync).not.toHaveBeenCalled();
    expect(openDatabaseAsync).not.toHaveBeenCalled();
  });

  test('generates one 256-bit key for a new database and stores it as device-only', async () => {
    const db = new FakeDatabase(0);
    let storedKey: string | null = null;
    let databaseExists = false;
    const randomBytes = Uint8Array.from({ length: 32 }, (_, index) => index);
    const getRandomBytesAsync = jest.fn(async () => randomBytes);
    const setItemAsync = jest.fn(async (_name: string, key: string) => {
      storedKey = key;
    });
    const openDatabaseAsync = jest.fn(async () => {
      databaseExists = true;
      return db;
    });
    const dependencies = {
      databaseFile: { exists: async () => databaseExists },
      secureStore: {
        getItemAsync: async () => storedKey,
        setItemAsync,
        whenUnlockedThisDeviceOnly: 42,
      },
      crypto: { getRandomBytesAsync },
      sqlite: { openDatabaseAsync },
    };

    await openDatabaseWithDependencies(dependencies);
    await openDatabaseWithDependencies(dependencies);

    expect(getRandomBytesAsync).toHaveBeenCalledTimes(1);
    expect(storedKey).toBe(
      '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f',
    );
    expect(setItemAsync).toHaveBeenCalledWith('taisa.database-key.v1', storedKey, {
      keychainAccessible: 42,
    });
    expect(db.calls[0]).toBe(`PRAGMA key = "x'${storedKey}'"`);
    expect(db.calls).toContain('PRAGMA foreign_keys = ON');
    expect(db.calls).toContain('PRAGMA journal_mode = WAL');
  });

  test('treats an invalid stored key for an existing database as recovery-required', async () => {
    const db = new FakeDatabase(0);
    const openDatabaseAsync = jest.fn(async () => db);

    await expect(
      openDatabaseWithDependencies({
        databaseFile: { exists: async () => true },
        secureStore: {
          getItemAsync: async () => 'not-a-sqlcipher-key',
          setItemAsync: async () => undefined,
          whenUnlockedThisDeviceOnly: 42,
        },
        crypto: { getRandomBytesAsync: async () => new Uint8Array(32) },
        sqlite: { openDatabaseAsync },
      }),
    ).rejects.toMatchObject({
      code: 'DATABASE_RECOVERY_REQUIRED',
      reason: 'invalid-key',
    });
    expect(openDatabaseAsync).not.toHaveBeenCalled();
  });

  test('closes an existing database and requires recovery when its key cannot decrypt it', async () => {
    const db = new FakeDatabase(0);
    db.getFirstAsync = async <T>(source: string) => {
      if (source === 'PRAGMA cipher_version') {
        return { cipher_version: '4.6.1' } as T;
      }
      throw new Error('file is not a database');
    };

    await expect(
      openDatabaseWithDependencies({
        databaseFile: { exists: async () => true },
        secureStore: {
          getItemAsync: async () => validKey,
          setItemAsync: async () => undefined,
          whenUnlockedThisDeviceOnly: 42,
        },
        crypto: { getRandomBytesAsync: async () => new Uint8Array(32) },
        sqlite: { openDatabaseAsync: async () => db },
      }),
    ).rejects.toMatchObject({
      code: 'DATABASE_RECOVERY_REQUIRED',
      reason: 'unreadable-database',
    });
    expect(db.closed).toBe(true);
  });

  test('shares a concurrent open, then close clears the cached handle for a fresh reopen', async () => {
    const openedDatabases: FakeDatabase[] = [];
    const lifecycle = createDatabaseLifecycle({
      databaseFile: { exists: async () => true },
      secureStore: {
        getItemAsync: async () => validKey,
        setItemAsync: async () => undefined,
        whenUnlockedThisDeviceOnly: 42,
      },
      crypto: { getRandomBytesAsync: async () => new Uint8Array(32) },
      sqlite: {
        openDatabaseAsync: async () => {
          const db = new FakeDatabase(1);
          openedDatabases.push(db);
          return db;
        },
      },
    });

    const firstOpening = lifecycle.open();
    const concurrentOpening = lifecycle.open();

    expect(concurrentOpening).toBe(firstOpening);
    const firstDatabase = await firstOpening;
    expect(openedDatabases).toHaveLength(1);

    await lifecycle.close();
    expect(firstDatabase.closed).toBe(true);

    const secondDatabase = await lifecycle.open();
    expect(secondDatabase).not.toBe(firstDatabase);
    expect(openedDatabases).toHaveLength(2);
  });
});

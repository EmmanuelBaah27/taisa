import * as Crypto from 'expo-crypto';
import { File } from 'expo-file-system';
import * as SecureStore from 'expo-secure-store';
import * as SQLite from 'expo-sqlite';
import type { SQLiteDatabase } from 'expo-sqlite';

import { runMigrations } from './migrations';
import type { ClosableDatabaseLike } from './types';
import { recoverInterruptedArchivePromotion } from '../services/archiveFileStore';

const DATABASE_NAME = 'taisa-local.db';
const KEY_NAME = 'taisa.database-key.v1';
const SQLCIPHER_KEY_PATTERN = /^[0-9a-f]{64}$/i;

export type DatabaseRecoveryReason =
  | 'missing-key'
  | 'invalid-key'
  | 'key-store-unavailable'
  | 'unreadable-database';
export type DatabaseConfigurationReason = 'sqlcipher-unavailable' | 'secure-store-unavailable';

export class DatabaseConfigurationRequiredError extends Error {
  readonly code = 'DATABASE_CONFIGURATION_REQUIRED';

  constructor(readonly reason: DatabaseConfigurationReason, options?: { cause?: unknown }) {
    super('This build cannot safely open the encrypted local archive.', options);
    this.name = 'DatabaseConfigurationRequiredError';
  }
}

export class DatabaseRecoveryRequiredError extends Error {
  readonly code = 'DATABASE_RECOVERY_REQUIRED';

  constructor(
    readonly reason: DatabaseRecoveryReason,
    options?: { cause?: unknown },
  ) {
    super('The encrypted local archive requires recovery.', options);
    this.name = 'DatabaseRecoveryRequiredError';
  }
}

interface DatabaseFileBoundary {
  exists(databaseName: string): Promise<boolean>;
}

interface SecureStoreBoundary {
  readonly whenUnlockedThisDeviceOnly: SecureStore.KeychainAccessibilityConstant;
  getItemAsync(key: string): Promise<string | null>;
  setItemAsync(
    key: string,
    value: string,
    options: { keychainAccessible: SecureStore.KeychainAccessibilityConstant },
  ): Promise<void>;
}

interface CryptoBoundary {
  getRandomBytesAsync(byteCount: number): Promise<Uint8Array>;
}

interface SQLiteBoundary<TDatabase extends ClosableDatabaseLike> {
  openDatabaseAsync(databaseName: string): Promise<TDatabase>;
}

export interface OpenDatabaseDependencies<TDatabase extends ClosableDatabaseLike> {
  readonly databaseFile: DatabaseFileBoundary;
  readonly secureStore: SecureStoreBoundary;
  readonly crypto: CryptoBoundary;
  readonly sqlite: SQLiteBoundary<TDatabase>;
}

export interface DatabaseLifecycle<TDatabase extends ClosableDatabaseLike> {
  open(): Promise<TDatabase>;
  close(): Promise<void>;
}

export class DatabaseMaintenanceInProgressError extends Error {
  readonly code = 'DATABASE_MAINTENANCE_IN_PROGRESS';

  constructor() {
    super('The local archive is temporarily unavailable while recovery is running.');
    this.name = 'DatabaseMaintenanceInProgressError';
  }
}

export interface DatabaseAccessCoordinator<TDatabase extends ClosableDatabaseLike> {
  withDatabase<T>(work: (database: TDatabase) => Promise<T>): Promise<T>;
  withMaintenance<T>(work: () => Promise<T>): Promise<T>;
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
}

async function loadOrCreateKey<TDatabase extends ClosableDatabaseLike>(
  databaseExists: boolean,
  dependencies: OpenDatabaseDependencies<TDatabase>,
): Promise<string> {
  let existingKey: string | null;
  try {
    existingKey = await dependencies.secureStore.getItemAsync(KEY_NAME);
  } catch (cause) {
    if (databaseExists) {
      throw new DatabaseRecoveryRequiredError('key-store-unavailable', { cause });
    }
    throw new DatabaseConfigurationRequiredError('secure-store-unavailable', { cause });
  }
  if (existingKey !== null) {
    if (!SQLCIPHER_KEY_PATTERN.test(existingKey)) {
      throw new DatabaseRecoveryRequiredError('invalid-key');
    }
    return existingKey.toLowerCase();
  }

  if (databaseExists) {
    throw new DatabaseRecoveryRequiredError('missing-key');
  }

  const bytes = await dependencies.crypto.getRandomBytesAsync(32);
  if (bytes.length !== 32) {
    throw new Error('Secure random source did not return a 256-bit key');
  }
  const key = bytesToHex(bytes);
  await dependencies.secureStore.setItemAsync(KEY_NAME, key, {
    keychainAccessible: dependencies.secureStore.whenUnlockedThisDeviceOnly,
  });
  return key;
}

async function applyEncryptionKeyAndValidate(
  db: ClosableDatabaseLike,
  key: string,
  databaseExists: boolean,
): Promise<void> {
  // SQLCipher does not accept a bound parameter for PRAGMA key. The only interpolated value
  // passes the fixed 64-character hexadecimal allowlist above.
  await db.execAsync(`PRAGMA key = "x'${key}'"`);
  const cipher = await db.getFirstAsync<{ cipher_version: string }>('PRAGMA cipher_version');
  if (typeof cipher?.cipher_version !== 'string' || cipher.cipher_version.trim().length === 0) {
    throw new DatabaseConfigurationRequiredError('sqlcipher-unavailable');
  }
  try {
    await db.getFirstAsync<{ count: number }>('SELECT count(*) AS count FROM sqlite_master');
  } catch (cause) {
    if (databaseExists) {
      throw new DatabaseRecoveryRequiredError('unreadable-database', { cause });
    }
    throw cause;
  }
}

export async function openDatabaseWithDependencies<TDatabase extends ClosableDatabaseLike>(
  dependencies: OpenDatabaseDependencies<TDatabase>,
): Promise<TDatabase> {
  const databaseExists = await dependencies.databaseFile.exists(DATABASE_NAME);
  const key = await loadOrCreateKey(databaseExists, dependencies);
  const db = await dependencies.sqlite.openDatabaseAsync(DATABASE_NAME);

  try {
    await applyEncryptionKeyAndValidate(db, key, databaseExists);
    await db.execAsync('PRAGMA foreign_keys = ON');
    await db.execAsync('PRAGMA journal_mode = WAL');
    await runMigrations(db);
    return db;
  } catch (error) {
    await db.closeAsync();
    throw error;
  }
}

export function createDatabaseLifecycle<TDatabase extends ClosableDatabaseLike>(
  dependencies: OpenDatabaseDependencies<TDatabase>,
): DatabaseLifecycle<TDatabase> {
  let activeOpening: Promise<TDatabase> | null = null;
  let activeClosing: Promise<void> | null = null;

  function open(): Promise<TDatabase> {
    if (activeClosing !== null) {
      return activeClosing.then(open);
    }
    if (activeOpening !== null) {
      return activeOpening;
    }

    const opening = openDatabaseWithDependencies(dependencies);
    activeOpening = opening;
    void opening.catch(() => {
      if (activeOpening === opening) {
        activeOpening = null;
      }
    });
    return opening;
  }

  function close(): Promise<void> {
    if (activeClosing !== null) {
      return activeClosing;
    }
    const opening = activeOpening;
    if (opening === null) {
      return Promise.resolve();
    }

    const closing = (async () => {
      try {
        const db = await opening;
        await db.closeAsync();
      } finally {
        if (activeOpening === opening) {
          activeOpening = null;
        }
        activeClosing = null;
      }
    })();
    activeClosing = closing;
    return closing;
  }

  return {
    open,
    close,
  };
}

export function createDatabaseAccessCoordinator<TDatabase extends ClosableDatabaseLike>(
  lifecycle: DatabaseLifecycle<TDatabase>,
): DatabaseAccessCoordinator<TDatabase> {
  let maintenanceRequested = false;
  let activeOperations = 0;
  const idleWaiters = new Set<() => void>();

  function notifyIdle(): void {
    if (activeOperations !== 0) return;
    for (const resolve of idleWaiters) resolve();
    idleWaiters.clear();
  }

  async function waitUntilIdle(): Promise<void> {
    if (activeOperations === 0) return;
    await new Promise<void>((resolve) => { idleWaiters.add(resolve); });
  }

  return {
    async withDatabase(work) {
      if (maintenanceRequested) throw new DatabaseMaintenanceInProgressError();
      activeOperations += 1;
      try {
        const database = await lifecycle.open();
        return await work(database);
      } finally {
        activeOperations -= 1;
        notifyIdle();
      }
    },
    async withMaintenance(work) {
      if (maintenanceRequested) throw new DatabaseMaintenanceInProgressError();
      maintenanceRequested = true;
      try {
        await waitUntilIdle();
        return await work();
      } finally {
        maintenanceRequested = false;
      }
    },
  };
}

const nativeDependencies: OpenDatabaseDependencies<SQLiteDatabase> = {
  databaseFile: {
    async exists(databaseName: string): Promise<boolean> {
      await recoverInterruptedArchivePromotion();
      const directory = SQLite.defaultDatabaseDirectory;
      if (typeof directory !== 'string' || directory.length === 0) {
        throw new Error('SQLite database directory is unavailable on this platform');
      }
      return new File(directory, databaseName).exists;
    },
  },
  secureStore: {
    whenUnlockedThisDeviceOnly: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
    getItemAsync: SecureStore.getItemAsync,
    setItemAsync: SecureStore.setItemAsync,
  },
  crypto: {
    getRandomBytesAsync: Crypto.getRandomBytesAsync,
  },
  sqlite: {
    openDatabaseAsync: SQLite.openDatabaseAsync,
  },
};

const databaseLifecycle = createDatabaseLifecycle(nativeDependencies);
const databaseAccess = createDatabaseAccessCoordinator(databaseLifecycle);

export function openTaisaDatabase(): Promise<SQLiteDatabase> {
  return databaseLifecycle.open();
}

export function closeTaisaDatabase(): Promise<void> {
  return databaseLifecycle.close();
}

export function withTaisaDatabase<T>(
  work: (database: SQLiteDatabase) => Promise<T>,
): Promise<T> {
  return databaseAccess.withDatabase(work);
}

export function withTaisaMaintenance<T>(work: () => Promise<T>): Promise<T> {
  return databaseAccess.withMaintenance(work);
}

import {
  SCHEMA_V1_STATEMENTS,
  SCHEMA_V2_STATEMENTS,
  SCHEMA_V3_STATEMENTS,
  SCHEMA_V4_STATEMENTS,
} from './schema';
import type { DatabaseLike } from './types';

export const SCHEMA_VERSION = 4;

interface Migration {
  readonly version: number;
  readonly versionStatement: string;
  readonly statements: readonly string[];
}

const MIGRATIONS: readonly Migration[] = [
  {
    version: 1,
    versionStatement: 'PRAGMA user_version = 1',
    statements: SCHEMA_V1_STATEMENTS,
  },
  {
    version: 2,
    versionStatement: 'PRAGMA user_version = 2',
    statements: SCHEMA_V2_STATEMENTS,
  },
  {
    version: 3,
    versionStatement: 'PRAGMA user_version = 3',
    statements: SCHEMA_V3_STATEMENTS,
  },
  {
    version: 4,
    versionStatement: 'PRAGMA user_version = 4',
    statements: SCHEMA_V4_STATEMENTS,
  },
];

export class UnsupportedDatabaseVersionError extends Error {
  readonly code = 'UNSUPPORTED_DATABASE_VERSION';

  constructor(readonly databaseVersion: number) {
    super(`Database schema version ${databaseVersion} is newer than supported version ${SCHEMA_VERSION}`);
    this.name = 'UnsupportedDatabaseVersionError';
  }
}

async function readUserVersion(db: DatabaseLike): Promise<number> {
  const row = await db.getFirstAsync<{ user_version: number }>('PRAGMA user_version');
  const version = row?.user_version;
  if (!Number.isSafeInteger(version) || version === undefined || version < 0) {
    throw new Error('Database returned an invalid user_version');
  }
  return version;
}

async function applyMigration(db: DatabaseLike, migration: Migration): Promise<void> {
  await db.execAsync('BEGIN IMMEDIATE');
  try {
    for (const statement of migration.statements) {
      await db.execAsync(statement);
    }
    await db.execAsync(migration.versionStatement);
    await db.execAsync('COMMIT');
  } catch (error) {
    await db.execAsync('ROLLBACK');
    throw error;
  }
}

export async function runMigrations(
  db: DatabaseLike,
  targetVersion: number = SCHEMA_VERSION,
): Promise<void> {
  if (!Number.isSafeInteger(targetVersion) || targetVersion < 1 || targetVersion > SCHEMA_VERSION) {
    throw new UnsupportedDatabaseVersionError(targetVersion);
  }
  const currentVersion = await readUserVersion(db);
  if (currentVersion > targetVersion) {
    throw new UnsupportedDatabaseVersionError(currentVersion);
  }

  for (const migration of MIGRATIONS) {
    if (migration.version > currentVersion && migration.version <= targetVersion) {
      await applyMigration(db, migration);
    }
  }
}

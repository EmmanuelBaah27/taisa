import Database from 'better-sqlite3';

import {
  SCHEMA_V1_STATEMENTS,
  SCHEMA_V2_STATEMENTS,
  SCHEMA_V3_STATEMENTS,
  SCHEMA_V4_STATEMENTS,
} from '../../db/schema';
import type {
  ExclusiveTransactionConnection,
  RepositoryConnection,
  RepositoryTransaction,
  SQLiteBindParams,
} from '../../db/types';
import { withRepositoryTransaction } from '../../db/types';

function normalizeParams(params: SQLiteBindParams): SQLiteBindParams {
  if (Array.isArray(params)) {
    return params;
  }

  return Object.fromEntries(
    Object.entries(params).map(([key, value]) => [key.replace(/^[$:@]/, ''), value]),
  );
}

export interface TestDatabase extends ExclusiveTransactionConnection {
  close(): void;
  withTransaction<T>(work: (transaction: RepositoryTransaction) => Promise<T>): Promise<T>;
}

export function createTestDatabase(): TestDatabase {
  const database = new Database(':memory:');
  database.pragma('foreign_keys = ON');
  for (const statement of SCHEMA_V1_STATEMENTS) {
    database.exec(statement);
  }
  for (const statement of SCHEMA_V2_STATEMENTS) {
    database.exec(statement);
  }
  for (const statement of SCHEMA_V3_STATEMENTS) {
    database.exec(statement);
  }
  for (const statement of SCHEMA_V4_STATEMENTS) {
    database.exec(statement);
  }

  const connection: TestDatabase = {
    async execAsync(source: string): Promise<void> {
      database.exec(source);
    },
    async runAsync(source: string, params: SQLiteBindParams = []): Promise<{ changes: number; lastInsertRowId: number }> {
      const result = database.prepare(source).run(normalizeParams(params));
      return {
        changes: result.changes,
        lastInsertRowId: Number(result.lastInsertRowid),
      };
    },
    async getFirstAsync<T>(source: string, params: SQLiteBindParams = []): Promise<T | null> {
      return (database.prepare(source).get(normalizeParams(params)) as T | undefined) ?? null;
    },
    async getAllAsync<T>(source: string, params: SQLiteBindParams = []): Promise<T[]> {
      return database.prepare(source).all(normalizeParams(params)) as T[];
    },
    close(): void {
      database.close();
    },
    async withExclusiveTransactionAsync(
      work: (transaction: RepositoryConnection) => Promise<void>,
    ): Promise<void> {
      database.exec('BEGIN IMMEDIATE');
      try {
        await work(connection);
        database.exec('COMMIT');
      } catch (error) {
        database.exec('ROLLBACK');
        throw error;
      }
    },
    withTransaction<T>(work: (transaction: RepositoryTransaction) => Promise<T>): Promise<T> {
      return withRepositoryTransaction(connection, work);
    },
  };

  return connection;
}

export const NOW = '2026-08-10T09:00:00.000Z';
export const LATER = '2026-08-10T10:00:00.000Z';

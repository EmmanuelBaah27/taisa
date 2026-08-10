export type SQLiteBindValue = string | number | null | boolean | Uint8Array;
export type SQLiteBindParams = Record<string, SQLiteBindValue> | SQLiteBindValue[];

export interface SQLiteRunResultLike {
  readonly lastInsertRowId: number;
  readonly changes: number;
}

export interface DatabaseLike {
  execAsync(source: string): Promise<void>;
  getFirstAsync<T>(source: string, params?: SQLiteBindParams): Promise<T | null>;
}

export interface ClosableDatabaseLike extends DatabaseLike {
  closeAsync(): Promise<void>;
}

export interface RepositoryConnection extends DatabaseLike {
  runAsync(source: string, params?: SQLiteBindParams): Promise<SQLiteRunResultLike>;
  getAllAsync<T>(source: string, params?: SQLiteBindParams): Promise<T[]>;
}

// Expo SQLite's exclusive transaction object exposes the same bound-query methods as its
// database connection. Naming the narrower contract makes mutation boundaries explicit.
export type RepositoryTransaction = RepositoryConnection;

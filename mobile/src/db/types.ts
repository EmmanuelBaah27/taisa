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

declare const repositoryTransactionBrand: unique symbol;

export interface RepositoryTransaction extends RepositoryConnection {
  readonly [repositoryTransactionBrand]: true;
}

export interface ExclusiveTransactionConnection extends RepositoryConnection {
  withExclusiveTransactionAsync(
    work: (transaction: RepositoryConnection) => Promise<void>,
  ): Promise<void>;
}

export async function withRepositoryTransaction<T>(
  database: ExclusiveTransactionConnection,
  work: (transaction: RepositoryTransaction) => Promise<T>,
): Promise<T> {
  let completed = false;
  let result!: T;
  await database.withExclusiveTransactionAsync(async (transaction) => {
    result = await work(transaction as RepositoryTransaction);
    completed = true;
  });
  if (!completed) {
    throw new Error('Exclusive repository transaction did not execute');
  }
  return result;
}

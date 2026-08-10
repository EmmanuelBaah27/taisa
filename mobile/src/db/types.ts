export interface DatabaseLike {
  execAsync(source: string): Promise<void>;
  getFirstAsync<T>(source: string): Promise<T | null>;
}

export interface ClosableDatabaseLike extends DatabaseLike {
  closeAsync(): Promise<void>;
}

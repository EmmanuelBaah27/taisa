import type { SQLiteBindParams, SQLiteBindValue } from '../db/types';

export function parseStringArray(value: string, column: string): string[] {
  const parsed: unknown = JSON.parse(value);
  if (!Array.isArray(parsed) || parsed.some((item) => typeof item !== 'string')) {
    throw new Error(`Invalid string-array JSON in ${column}`);
  }
  return parsed;
}

export function lifecycleFilter<T extends string>(
  column: string,
  values: readonly T[] | undefined,
): { clause: string; params: SQLiteBindParams } {
  if (values === undefined) {
    return { clause: '', params: [] };
  }
  if (values.length === 0) {
    return { clause: ' WHERE 0', params: [] };
  }

  const params: Record<string, SQLiteBindValue> = {};
  const placeholders = values.map((value, index) => {
    const key = `$lifecycle${index}`;
    params[key] = value;
    return key;
  });
  return {
    clause: ` WHERE ${column} IN (${placeholders.join(', ')})`,
    params,
  };
}

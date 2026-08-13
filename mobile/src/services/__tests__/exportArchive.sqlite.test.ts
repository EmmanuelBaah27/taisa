import { createHash } from 'crypto';
import { mkdtempSync, rmSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import Database from 'better-sqlite3';
import type { SQLiteDatabase } from 'expo-sqlite';

import { SCHEMA_V1_STATEMENTS, SCHEMA_V2_STATEMENTS } from '../../db/schema';
import {
  createSqlCipherArchiveBoundary,
  schemaSqlMatchesExactly,
  type ArchiveSnapshot,
} from '../exportArchive';

const TABLES = [
  ['profile', 'id'], ['conversations', 'id'], ['messages', 'id'], ['goals', 'id'],
  ['milestones', 'id'], ['actions', 'id'], ['action_transitions', 'id'],
  ['evidence', 'id'], ['memory_items', 'id'], ['memory_sources', 'id'],
  ['memory_confirmations', 'id'], ['coaching_requests', 'id'],
  ['audio_cleanup_queue', 'audio_uri'], ['usage_receipts', 'id'],
  ['migration_state', 'id'], ['mutation_receipts', 'idempotency_id'],
] as const;
const NOW = '2026-08-10T09:00:00.000Z';
const hash = (value: string) => createHash('sha256').update(value).digest('hex');

function migrate(database: Database.Database): void {
  database.pragma('foreign_keys = ON');
  SCHEMA_V1_STATEMENTS.forEach((statement) => database.exec(statement));
  SCHEMA_V2_STATEMENTS.forEach((statement) => database.exec(statement));
  database.pragma('user_version = 2');
}

function fingerprint(database: Database.Database): ArchiveSnapshot {
  const counts = {} as ArchiveSnapshot['counts'];
  const canonical: unknown[] = [];
  for (const [table, order] of TABLES) {
    const rows = database.prepare(`SELECT * FROM "${table}" ORDER BY "${order}"`).all();
    counts[table] = rows.length;
    canonical.push([table, rows]);
  }
  return { archiveFormatVersion: 1, schemaVersion: 2, counts, contentHash: hash(JSON.stringify(canonical)) };
}

function addManifest(database: Database.Database, value: ArchiveSnapshot): void {
  database.exec(`CREATE TABLE taisa_archive_manifest (
    id INTEGER PRIMARY KEY NOT NULL, archive_format_version INTEGER NOT NULL,
    schema_version INTEGER NOT NULL, counts_json TEXT NOT NULL,
    content_hash TEXT NOT NULL, created_at TEXT NOT NULL)`);
  database.prepare(`INSERT INTO taisa_archive_manifest VALUES (1, 1, 2, ?, ?, ?)`)
    .run(JSON.stringify(value.counts), value.contentHash, NOW);
}

function populate(database: Database.Database): void {
  database.prepare(`INSERT INTO profile (id, created_at, updated_at) VALUES ('p', ?, ?)`).run(NOW, NOW);
  database.prepare(`INSERT INTO conversations
    (id, lifecycle, preferred_input_mode, created_at, updated_at)
    VALUES ('c', 'active', 'voice', ?, ?)`).run(NOW, NOW);
  database.prepare(`INSERT INTO messages
    (id, conversation_id, role, content, lifecycle, created_at, updated_at)
    VALUES ('z-parent', 'c', 'user', 'Parent thought', 'submitted', ?, ?)`).run(NOW, NOW);
  database.prepare(`INSERT INTO messages
    (id, conversation_id, parent_message_id, role, content, lifecycle, created_at, updated_at)
    VALUES ('a-child', 'c', 'z-parent', 'assistant', 'Child response', 'received', ?, ?)`).run(NOW, NOW);
  database.prepare(`INSERT INTO goals
    (id, title, lifecycle, created_at, updated_at, status_changed_at)
    VALUES ('z-goal', 'Earlier', 'superseded', ?, ?, ?)`).run(NOW, NOW, NOW);
  database.prepare(`INSERT INTO goals
    (id, title, lifecycle, supersedes_id, created_at, updated_at, status_changed_at)
    VALUES ('a-goal', 'Current', 'active', 'z-goal', ?, ?, ?)`).run(NOW, NOW, NOW);
  database.prepare(`INSERT INTO actions
    (id, title, lifecycle, created_at, updated_at, status_changed_at)
    VALUES ('z-action', 'Earlier', 'archived', ?, ?, ?)`).run(NOW, NOW, NOW);
  database.prepare(`INSERT INTO actions
    (id, title, lifecycle, supersedes_id, created_at, updated_at, status_changed_at)
    VALUES ('a-action', 'Current', 'open', 'z-action', ?, ?, ?)`).run(NOW, NOW, NOW);
  database.prepare(`INSERT INTO memory_items
    (id, type, statement, provenance, lifecycle, confidence, created_at,
     last_supported_at, status_changed_at, updated_at)
    VALUES ('z-memory', 'goal', 'Earlier', 'user-confirmed', 'superseded',
      'established', ?, ?, ?, ?)`).run(NOW, NOW, NOW, NOW);
  database.prepare(`INSERT INTO memory_items
    (id, type, statement, provenance, lifecycle, confidence, supersedes_id, created_at,
     last_supported_at, status_changed_at, updated_at)
    VALUES ('a-memory', 'goal', 'Current', 'user-confirmed', 'active',
      'established', 'z-memory', ?, ?, ?, ?)`).run(NOW, NOW, NOW, NOW);
  database.prepare(`INSERT INTO evidence
    (id, statement, occurred_at, created_at, updated_at)
    VALUES ('e', 'Led launch', ?, ?, ?)`).run(NOW, NOW, NOW);
}

function adapter(database: Database.Database, cipher = false, corruptCandidate = false) {
  let importing = false;
  return {
    async execAsync(sql: string) {
      if (sql === 'BEGIN IMMEDIATE') importing = true;
      database.exec(sql);
      if (sql === 'COMMIT' && importing && corruptCandidate) {
        database.prepare(`INSERT INTO evidence_search(evidence_search) VALUES ('delete-all')`).run();
      }
    },
    async runAsync(sql: string, params: readonly unknown[] = []) {
      const actual = sql === 'ATTACH DATABASE ? AS source_archive KEY ?'
        ? 'ATTACH DATABASE ? AS source_archive' : sql;
      const actualParams = actual === sql ? params : [params[0]];
      const result = database.prepare(actual).run(...actualParams);
      return { changes: result.changes, lastInsertRowId: Number(result.lastInsertRowid) };
    },
    async getFirstAsync<T>(sql: string, params: readonly unknown[] = []): Promise<T | null> {
      if (cipher && sql === 'PRAGMA cipher_version') return { cipher_version: 'test' } as T;
      return (database.prepare(sql).get(...params) as T | undefined) ?? null;
    },
    async getAllAsync<T>(sql: string, params: readonly unknown[] = []): Promise<T[]> {
      return database.prepare(sql).all(...params) as T[];
    },
    async closeAsync() { database.close(); },
  } as unknown as Pick<
    SQLiteDatabase,
    'execAsync' | 'runAsync' | 'getFirstAsync' | 'getAllAsync' | 'closeAsync'
  >;
}

describe('real SQLite archive boundaries', () => {
  let directory: string;
  let sourcePath: string;
  let candidatePath: string;

  beforeEach(() => {
    directory = mkdtempSync(join(tmpdir(), 'taisa-archive-'));
    sourcePath = join(directory, 'source.db');
    candidatePath = join(directory, 'candidate.db');
  });
  afterEach(() => rmSync(directory, { recursive: true, force: true }));

  function makeBoundary(corruptCandidate = false) {
    return createSqlCipherArchiveBoundary({
      openActive: async () => adapter(new Database(':memory:')),
      openMaintenance: async () => adapter(new Database(':memory:'), true),
      openDeviceCandidate: async () => {
        const database = new Database(candidatePath);
        migrate(database);
        return adapter(database, false, corruptCandidate);
      },
      deleteMaintenance: async () => undefined,
      readDeviceKey: async () => 'b'.repeat(64),
      sha256: async (value) => hash(value),
    });
  }

  function createSource(populated = true): ArchiveSnapshot {
    const database = new Database(sourcePath);
    migrate(database);
    if (populated) populate(database);
    const value = fingerprint(database);
    addManifest(database, value);
    database.close();
    return value;
  }

  test('round-trips later-ID parents and superseded goal/action/memory references', async () => {
    const expected = createSource();
    await expect(makeBoundary().createDeviceEncryptedCandidate({
      sourceUri: sourcePath, destinationUri: candidatePath, passphrase: 'long passphrase',
    })).resolves.toEqual(expected);
    const candidate = new Database(candidatePath, { readonly: true });
    expect(candidate.prepare(`SELECT parent_message_id FROM messages WHERE id='a-child'`).get())
      .toEqual({ parent_message_id: 'z-parent' });
    expect(candidate.prepare(`SELECT supersedes_id FROM goals WHERE id='a-goal'`).get())
      .toEqual({ supersedes_id: 'z-goal' });
    expect(candidate.prepare(`SELECT supersedes_id FROM actions WHERE id='a-action'`).get())
      .toEqual({ supersedes_id: 'z-action' });
    expect(candidate.prepare(`SELECT supersedes_id FROM memory_items WHERE id='a-memory'`).get())
      .toEqual({ supersedes_id: 'z-memory' });
    expect(candidate.prepare(`SELECT preferred_input_mode FROM conversations WHERE id='c'`).get())
      .toEqual({ preferred_input_mode: 'voice' });
    expect(candidate.pragma('foreign_key_check')).toEqual([]);
    candidate.close();
  });

  test('rejects a corrupted source message FTS index', async () => {
    createSource();
    const source = new Database(sourcePath);
    source.prepare(`INSERT INTO message_search(message_search) VALUES ('delete-all')`).run();
    source.close();
    await expect(makeBoundary().inspectPassphraseArchive({
      sourceUri: sourcePath, passphrase: 'long passphrase',
    })).rejects.toThrow(/search index/i);
  });

  test('rejects a corrupted rebuilt evidence FTS index', async () => {
    createSource();
    await expect(makeBoundary(true).createDeviceEncryptedCandidate({
      sourceUri: sourcePath, destinationUri: candidatePath, passphrase: 'long passphrase',
    })).rejects.toThrow(/search index/i);
  });

  test.each([
    ['view', `ALTER TABLE profile RENAME TO profile_data;
      CREATE VIEW profile AS SELECT * FROM profile_data`],
    ['virtual table', `DROP TABLE profile;
      CREATE VIRTUAL TABLE profile USING fts5(id, current_role, current_company, industry,
      years_of_experience, career_stage, current_focus_area, short_term_goal, long_term_goal,
      coaching_style, accountability_level, reminder_times_json, created_at, updated_at)`],
    ['unexpected object', `CREATE VIEW archive_owned_helper AS SELECT id FROM profile`],
  ])('rejects a source %s substitution/object', async (_name, sql) => {
    createSource(false);
    const source = new Database(sourcePath);
    source.exec(sql);
    source.close();
    await expect(makeBoundary().createDeviceEncryptedCandidate({
      sourceUri: sourcePath, destinationUri: candidatePath, passphrase: 'long passphrase',
    })).rejects.toThrow(/trusted schema/i);
  });

  test('compares source schema SQL as exact inert text without folding quoted literals', async () => {
    expect(schemaSqlMatchesExactly(
      `CREATE TABLE sample (value TEXT DEFAULT 'ABC  DEF')`,
      `CREATE TABLE sample (value TEXT DEFAULT 'abc def')`,
    )).toBe(false);
  });
});

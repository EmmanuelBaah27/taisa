import * as Crypto from 'expo-crypto';
import { File } from 'expo-file-system';
import * as SecureStore from 'expo-secure-store';
import * as SQLite from 'expo-sqlite';
import type { SQLiteDatabase } from 'expo-sqlite';

import { runMigrations, SCHEMA_VERSION } from '../db/migrations';
import {
  closeTaisaDatabase,
  openTaisaDatabase,
  withTaisaMaintenance,
} from '../db/openDatabase';
import { invalidateLocalCaptureService } from './localPlatform';
import {
  ACTIVE_DATABASE_NAME,
  createExpoArchiveFileBoundary,
  RESTORE_CANDIDATE_NAME,
  type ArchiveFileBoundary,
} from './archiveFileStore';

export const ARCHIVE_FORMAT_VERSION = 1;
const MINIMUM_PASSPHRASE_LENGTH = 12;
const FREE_SPACE_RESERVE_BYTES = 1024 * 1024;
const MAINTENANCE_DATABASE_NAME = 'taisa-archive-maintenance.db';
const DEVICE_KEY_NAME = 'taisa.database-key.v1';
const DEVICE_KEY_PATTERN = /^[0-9a-f]{64}$/i;

const ARCHIVE_TABLES = [
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
  'coaching_requests',
  'audio_cleanup_queue',
  'usage_receipts',
  'migration_state',
  'mutation_receipts',
] as const;

export type ArchiveTable = typeof ARCHIVE_TABLES[number];
export type ArchiveEntityCounts = Record<ArchiveTable, number>;

const TABLE_ORDER_COLUMNS: Record<ArchiveTable, string> = {
  profile: 'id',
  conversations: 'id',
  messages: 'id',
  goals: 'id',
  milestones: 'id',
  actions: 'id',
  action_transitions: 'id',
  evidence: 'id',
  memory_items: 'id',
  memory_sources: 'id',
  memory_confirmations: 'id',
  coaching_requests: 'id',
  audio_cleanup_queue: 'audio_uri',
  usage_receipts: 'id',
  migration_state: 'id',
  mutation_receipts: 'idempotency_id',
};

export interface ArchiveSnapshot {
  readonly archiveFormatVersion: 1;
  readonly schemaVersion: number;
  readonly counts: ArchiveEntityCounts;
  readonly contentHash: string;
}

export interface ConfirmedArchivePassphrase {
  readonly value: string;
  readonly confirmed: true;
}

export type ArchiveOperationCode =
  | 'PASSPHRASE_TOO_SHORT'
  | 'PASSPHRASE_CONFIRMATION_MISMATCH'
  | 'ARCHIVE_OPERATION_BUSY'
  | 'PENDING_VOICE_NOT_BACKED_UP'
  | 'INSUFFICIENT_FREE_SPACE'
  | 'INVALID_ARCHIVE_OR_PASSPHRASE'
  | 'UNSUPPORTED_ARCHIVE_VERSION'
  | 'ARCHIVE_VERIFICATION_FAILED'
  | 'RESTORE_VERIFICATION_FAILED'
  | 'RESTORE_FAILED';

const ARCHIVE_ERROR_MESSAGES: Record<ArchiveOperationCode, string> = {
  PASSPHRASE_TOO_SHORT: 'Archive passphrase must contain at least 12 characters.',
  PASSPHRASE_CONFIRMATION_MISMATCH: 'Archive passphrase confirmation must match.',
  ARCHIVE_OPERATION_BUSY: 'Another archive operation is already running.',
  PENDING_VOICE_NOT_BACKED_UP: 'Finish or abandon the pending voice submission before creating a backup.',
  INSUFFICIENT_FREE_SPACE: 'There is not enough free space to complete this archive operation.',
  INVALID_ARCHIVE_OR_PASSPHRASE: 'The encrypted archive could not be opened.',
  UNSUPPORTED_ARCHIVE_VERSION: 'This archive was created by a newer version of Taisa.',
  ARCHIVE_VERIFICATION_FAILED: 'The encrypted archive did not pass verification.',
  RESTORE_VERIFICATION_FAILED: 'The restored archive did not match the verified candidate.',
  RESTORE_FAILED: 'The active archive was preserved because restore did not complete.',
};

export class ArchiveOperationError extends Error {
  constructor(readonly code: ArchiveOperationCode) {
    super(ARCHIVE_ERROR_MESSAGES[code]);
    this.name = 'ArchiveOperationError';
  }
}

export function confirmArchivePassphrase(
  passphrase: string,
  confirmation: string,
): ConfirmedArchivePassphrase {
  validatePassphrase(passphrase);
  if (passphrase !== confirmation) {
    throw new ArchiveOperationError('PASSPHRASE_CONFIRMATION_MISMATCH');
  }
  return { value: passphrase, confirmed: true };
}

function validatePassphrase(passphrase: string): void {
  if (passphrase.length < MINIMUM_PASSPHRASE_LENGTH
    || passphrase.trim().length < MINIMUM_PASSPHRASE_LENGTH) {
    throw new ArchiveOperationError('PASSPHRASE_TOO_SHORT');
  }
}

export interface SqlCipherArchiveBoundary {
  assertExportable(): Promise<void>;
  exportPassphraseArchive(input: {
    destinationUri: string;
    passphrase: string;
  }): Promise<ArchiveSnapshot>;
  inspectPassphraseArchive(input: {
    sourceUri: string;
    passphrase: string;
  }): Promise<ArchiveSnapshot>;
  createDeviceEncryptedCandidate(input: {
    sourceUri: string;
    destinationUri: string;
    passphrase: string;
  }): Promise<ArchiveSnapshot>;
  checkpointActive(): Promise<void>;
  fingerprintActive(): Promise<ArchiveSnapshot>;
}

export interface ArchiveDatabaseLifecycleBoundary {
  withMaintenance<T>(work: () => Promise<T>): Promise<T>;
  invalidateClients(): Promise<void>;
  close(): Promise<void>;
  reopen(): Promise<void>;
}

export interface ArchiveDependencies {
  readonly files: ArchiveFileBoundary;
  readonly sqlCipher: SqlCipherArchiveBoundary;
  readonly lifecycle: ArchiveDatabaseLifecycleBoundary;
}

export interface EncryptedArchiveService {
  exportEncryptedArchive(passphrase: ConfirmedArchivePassphrase): Promise<{
    uri: string;
    snapshot: ArchiveSnapshot;
  }>;
  restoreEncryptedArchive(uri: string, passphrase: string): Promise<{
    snapshot: ArchiveSnapshot;
  }>;
}

function snapshotsMatch(left: ArchiveSnapshot, right: ArchiveSnapshot): boolean {
  if (left.archiveFormatVersion !== right.archiveFormatVersion
    || left.schemaVersion !== right.schemaVersion
    || left.contentHash !== right.contentHash) return false;
  return ARCHIVE_TABLES.every((table) => left.counts[table] === right.counts[table]);
}

function requireCurrentSnapshot(snapshot: ArchiveSnapshot): void {
  if (snapshot.archiveFormatVersion !== ARCHIVE_FORMAT_VERSION
    || snapshot.schemaVersion !== SCHEMA_VERSION) {
    throw new ArchiveOperationError('UNSUPPORTED_ARCHIVE_VERSION');
  }
}

function requireRestorableSnapshot(snapshot: ArchiveSnapshot): void {
  if (snapshot.archiveFormatVersion !== ARCHIVE_FORMAT_VERSION
    || snapshot.schemaVersion < 1
    || snapshot.schemaVersion > SCHEMA_VERSION) {
    throw new ArchiveOperationError('UNSUPPORTED_ARCHIVE_VERSION');
  }
}

function candidateMatchesVerifiedSource(
  source: ArchiveSnapshot,
  candidate: ArchiveSnapshot,
): boolean {
  if (candidate.archiveFormatVersion !== ARCHIVE_FORMAT_VERSION
    || candidate.schemaVersion !== SCHEMA_VERSION) return false;
  if (!ARCHIVE_TABLES.every((table) => source.counts[table] === candidate.counts[table])) {
    return false;
  }
  return source.schemaVersion !== candidate.schemaVersion || source.contentHash === candidate.contentHash;
}

async function requireFreeSpace(
  files: ArchiveFileBoundary,
  requiredBytes: number,
): Promise<void> {
  if (await files.availableDiskSpace() < requiredBytes) {
    throw new ArchiveOperationError('INSUFFICIENT_FREE_SPACE');
  }
}

export function createEncryptedArchiveService(
  dependencies: ArchiveDependencies,
): EncryptedArchiveService {
  let operationInFlight = false;

  async function exclusively<T>(operation: () => Promise<T>): Promise<T> {
    if (operationInFlight) throw new ArchiveOperationError('ARCHIVE_OPERATION_BUSY');
    operationInFlight = true;
    try {
      return await operation();
    } finally {
      operationInFlight = false;
    }
  }

  return {
    async exportEncryptedArchive(confirmedPassphrase) {
      return exclusively(() => dependencies.lifecycle.withMaintenance(async () => {
        if (confirmedPassphrase.confirmed !== true) {
          throw new ArchiveOperationError('PASSPHRASE_CONFIRMATION_MISMATCH');
        }
        validatePassphrase(confirmedPassphrase.value);
        await dependencies.sqlCipher.assertExportable();
        const activeSize = await dependencies.files.size(ACTIVE_DATABASE_NAME);
        await requireFreeSpace(
          dependencies.files,
          Math.ceil(activeSize * 1.25) + FREE_SPACE_RESERVE_BYTES,
        );
        const destinationUri = dependencies.files.createExportUri();
        try {
          const snapshot = await dependencies.sqlCipher.exportPassphraseArchive({
            destinationUri,
            passphrase: confirmedPassphrase.value,
          });
          requireCurrentSnapshot(snapshot);
          return { uri: destinationUri, snapshot };
        } catch (cause) {
          try {
            await dependencies.files.discardExport?.(destinationUri);
          } catch {
            // Never replace the authoritative content-safe failure with a filesystem path/error.
          }
          if (cause instanceof ArchiveOperationError) throw cause;
          throw new ArchiveOperationError('ARCHIVE_VERIFICATION_FAILED');
        }
      }));
    },

    async restoreEncryptedArchive(uri, passphrase) {
      return exclusively(() => dependencies.lifecycle.withMaintenance(async () => {
        validatePassphrase(passphrase);
        const [activeSize, selectedSize] = await Promise.all([
          dependencies.files.size(ACTIVE_DATABASE_NAME),
          dependencies.files.size(uri),
        ]);
        await requireFreeSpace(
          dependencies.files,
          activeSize + selectedSize * 2 + FREE_SPACE_RESERVE_BYTES,
        );

        let preparedPromotion = false;
        let activeClosed = false;
        let promotedDatabaseOpen = false;
        let stagedUri: string | null = null;
        let candidateUri: string | null = null;

        try {
          stagedUri = await dependencies.files.stageSelectedArchive(uri);
          let sourceSnapshot: ArchiveSnapshot;
          try {
            sourceSnapshot = await dependencies.sqlCipher.inspectPassphraseArchive({
              sourceUri: stagedUri,
              passphrase,
            });
          } catch (cause) {
            if (cause instanceof ArchiveOperationError) throw cause;
            throw new ArchiveOperationError('INVALID_ARCHIVE_OR_PASSPHRASE');
          }
          requireRestorableSnapshot(sourceSnapshot);

          candidateUri = dependencies.files.createCandidateUri();
          const candidateSnapshot = await dependencies.sqlCipher.createDeviceEncryptedCandidate({
            sourceUri: stagedUri,
            destinationUri: candidateUri,
            passphrase,
          });
          if (!candidateMatchesVerifiedSource(sourceSnapshot, candidateSnapshot)) {
            throw new ArchiveOperationError('ARCHIVE_VERIFICATION_FAILED');
          }

          await dependencies.sqlCipher.checkpointActive();
          await dependencies.lifecycle.invalidateClients();
          await dependencies.lifecycle.close();
          activeClosed = true;

          preparedPromotion = true;
          await dependencies.files.preparePromotion();
          await dependencies.files.promoteCandidate();
          await dependencies.lifecycle.reopen();
          promotedDatabaseOpen = true;
          const promotedSnapshot = await dependencies.sqlCipher.fingerprintActive();
          if (!snapshotsMatch(candidateSnapshot, promotedSnapshot)) {
            throw new ArchiveOperationError('RESTORE_VERIFICATION_FAILED');
          }
          await dependencies.files.commitPromotion();
          preparedPromotion = false;
          return { snapshot: promotedSnapshot };
        } catch (cause) {
          if (preparedPromotion) {
            try {
              if (promotedDatabaseOpen) {
                await dependencies.lifecycle.close();
                promotedDatabaseOpen = false;
              }
              await dependencies.files.rollbackPromotion();
            } catch {
              // The marker and preserved rollback remain authoritative. Never reopen a database
              // path whose rollback did not complete and verify.
              throw new ArchiveOperationError('RESTORE_FAILED');
            }
            try {
              await dependencies.lifecycle.reopen();
            } catch {
              throw new ArchiveOperationError('RESTORE_FAILED');
            }
            activeClosed = false;
          } else if (activeClosed) {
            try {
              await dependencies.lifecycle.reopen();
            } catch {
              throw new ArchiveOperationError('RESTORE_FAILED');
            }
            activeClosed = false;
          }

          if (cause instanceof ArchiveOperationError) throw cause;
          throw new ArchiveOperationError('RESTORE_FAILED');
        } finally {
          try {
            await dependencies.files.cleanupTemporaryFiles();
          } catch {
            // Restore cleanup is idempotent and startup recovery retries it. Once the marker has
            // been removed, a cleanup interruption must not turn a committed restore into a
            // reported failure; before commit it must not replace the authoritative safe error.
          }
          void stagedUri;
          void candidateUri;
        }
      }));
    },
  };
}

type ArchiveSqlDatabase = Pick<
  SQLiteDatabase,
  'execAsync' | 'runAsync' | 'getFirstAsync' | 'getAllAsync' | 'closeAsync'
>;

interface SqlCipherEngineDependencies {
  openActive(): Promise<ArchiveSqlDatabase>;
  openMaintenance(): Promise<ArchiveSqlDatabase>;
  openDeviceCandidate(input: {
    destinationUri: string;
    deviceKey: string;
    schemaVersion: number;
  }): Promise<ArchiveSqlDatabase>;
  deleteMaintenance(): Promise<void>;
  readDeviceKey(): Promise<string>;
  sha256(input: string): Promise<string>;
}

function qualified(schema: 'main' | 'passphrase_export' | 'source_archive' | 'device_candidate', table: string): string {
  return `"${schema}"."${table}"`;
}

async function fingerprintSchema(
  database: ArchiveSqlDatabase,
  schema: 'main' | 'passphrase_export' | 'source_archive' | 'device_candidate',
  sha256: (input: string) => Promise<string>,
  verifySearchIndexes = true,
): Promise<ArchiveSnapshot> {
  const versionRow = await database.getFirstAsync<{ user_version: number }>(
    `PRAGMA ${schema}.user_version`,
  );
  if (!Number.isSafeInteger(versionRow?.user_version) || versionRow!.user_version < 0) {
    throw new Error('Archive schema version is invalid');
  }

  const integrityRows = await database.getAllAsync<{ integrity_check: string }>(
    `PRAGMA ${schema}.integrity_check`,
  );
  if (integrityRows.length !== 1 || integrityRows[0].integrity_check !== 'ok') {
    throw new Error('Archive integrity check failed');
  }

  const foreignKeyFailures = await database.getAllAsync<Record<string, unknown>>(
    `PRAGMA ${schema}.foreign_key_check`,
  );
  if (foreignKeyFailures.length !== 0) {
    throw new Error('Archive foreign key verification failed');
  }

  const counts = {} as ArchiveEntityCounts;
  const canonicalTables: unknown[] = [];
  for (const table of ARCHIVE_TABLES) {
    const rows = await database.getAllAsync<Record<string, unknown>>(
      `SELECT * FROM ${qualified(schema, table)} ORDER BY "${TABLE_ORDER_COLUMNS[table]}"`,
    );
    counts[table] = rows.length;
    canonicalTables.push([table, rows]);
  }
  if (counts.profile > 1) {
    throw new Error('Archive must contain at most one authoritative local profile');
  }

  try {
    // For external-content FTS5 tables, rank=1 makes integrity-check compare the real index
    // against its content table. Reading the virtual table without MATCH only reads content.
    // Never issue these commands against a selected archive: only locally created trusted
    // schemas may execute virtual-table behavior. A trusted candidate rebuilds and verifies
    // both indexes after bound ordinary-table rows are imported.
    if (verifySearchIndexes) {
      for (const table of ['message_search', 'evidence_search'] as const) {
        await database.runAsync(
          `INSERT INTO ${qualified(schema, table)} (${quoteTrustedIdentifier(table)}, rank)
           VALUES ('integrity-check', 1)`,
        );
      }
    }
  } catch {
    throw new Error('Archive search index verification failed');
  }

  const contentHash = await sha256(JSON.stringify(canonicalTables));
  if (!/^[0-9a-f]{64}$/i.test(contentHash)) throw new Error('Archive hash is invalid');
  return {
    archiveFormatVersion: ARCHIVE_FORMAT_VERSION,
    schemaVersion: versionRow!.user_version,
    counts,
    contentHash: contentHash.toLowerCase(),
  };
}

export function parseArchiveManifestForValidation(row: {
  archive_format_version: number;
  schema_version: number;
  counts_json: string;
  content_hash: string;
}): ArchiveSnapshot {
  if (row.archive_format_version !== ARCHIVE_FORMAT_VERSION
    || !Number.isSafeInteger(row.schema_version)
    || !/^[0-9a-f]{64}$/i.test(row.content_hash)) {
    throw new Error('Archive manifest is invalid');
  }
  const parsed = JSON.parse(row.counts_json) as Record<string, unknown>;
  const counts = {} as ArchiveEntityCounts;
  if (row.schema_version === SCHEMA_VERSION
    && Object.keys(parsed).length !== ARCHIVE_TABLES.length) {
    throw new Error('Archive manifest count set is invalid');
  }
  for (const table of ARCHIVE_TABLES) {
    const count = parsed[table];
    if (!Number.isSafeInteger(count) || (count as number) < 0) {
      throw new Error('Archive manifest count is invalid');
    }
    counts[table] = count as number;
  }
  if (counts.profile > 1) {
    throw new Error('Archive must contain at most one authoritative local profile');
  }
  return {
    archiveFormatVersion: ARCHIVE_FORMAT_VERSION,
    schemaVersion: row.schema_version,
    counts,
    contentHash: row.content_hash.toLowerCase(),
  };
}

async function inspectAttachedArchive(
  database: ArchiveSqlDatabase,
  schema: 'passphrase_export' | 'source_archive' | 'device_candidate',
  sha256: (input: string) => Promise<string>,
  options: {
    manifest?: ArchiveSnapshot;
    verifySearchIndexes?: boolean;
  } = {},
): Promise<ArchiveSnapshot> {
  const manifest = options.manifest ?? await readAttachedArchiveManifest(database, schema);
  if (manifest.schemaVersion < 1 || manifest.schemaVersion > SCHEMA_VERSION) return manifest;
  const actual = await fingerprintSchema(
    database,
    schema,
    sha256,
    options.verifySearchIndexes ?? true,
  );
  if (!snapshotsMatch(manifest, actual)) throw new Error('Archive fingerprint does not match');
  return actual;
}

async function readAttachedArchiveManifest(
  database: ArchiveSqlDatabase,
  schema: 'passphrase_export' | 'source_archive' | 'device_candidate',
): Promise<ArchiveSnapshot> {
  const manifestRow = await database.getFirstAsync<{
    archive_format_version: number;
    schema_version: number;
    counts_json: string;
    content_hash: string;
  }>(
    `SELECT archive_format_version, schema_version, counts_json, content_hash
     FROM ${qualified(schema, 'taisa_archive_manifest')} WHERE id = 1`,
  );
  if (manifestRow === null) throw new Error('Archive manifest is missing');
  return parseArchiveManifestForValidation(manifestRow);
}

async function requireSqlCipher(database: ArchiveSqlDatabase): Promise<void> {
  const row = await database.getFirstAsync<{ cipher_version: string }>('PRAGMA cipher_version');
  if (typeof row?.cipher_version !== 'string' || row.cipher_version.trim().length === 0) {
    throw new Error('SQLCipher is unavailable');
  }
}

async function withMaintenanceDatabase<T>(
  dependencies: SqlCipherEngineDependencies,
  work: (database: ArchiveSqlDatabase) => Promise<T>,
): Promise<T> {
  const database = await dependencies.openMaintenance();
  try {
    await requireSqlCipher(database);
    await database.execAsync('PRAGMA temp_store = MEMORY');
    return await work(database);
  } finally {
    await database.closeAsync();
    await dependencies.deleteMaintenance();
  }
}

async function attachWithPassphrase(
  database: ArchiveSqlDatabase,
  uri: string,
  schema: 'passphrase_export' | 'source_archive',
  passphrase: string,
): Promise<void> {
  // Both user-controlled values are bound parameters. They are never interpolated into SQL.
  await database.runAsync(`ATTACH DATABASE ? AS ${schema} KEY ?`, [uri, passphrase]);
}

async function detachQuietly(
  database: ArchiveSqlDatabase,
  schema: 'passphrase_export' | 'source_archive' | 'device_candidate',
): Promise<void> {
  try {
    await database.execAsync(`DETACH DATABASE ${schema}`);
  } catch {
    // The operation error remains authoritative; maintenance close releases any attachment.
  }
}

interface TableInfoRow {
  readonly cid: number;
  readonly name: string;
  readonly type: string;
  readonly notnull: number;
  readonly dflt_value: string | null;
  readonly pk: number;
}

interface SchemaObjectRow {
  readonly type: string;
  readonly name: string;
  readonly tbl_name: string;
  readonly sql: string | null;
}

export function schemaSqlMatchesExactly(left: string | null, right: string | null): boolean {
  return left === right;
}

async function schemaObjects(
  database: ArchiveSqlDatabase,
  schema: 'main' | 'source_archive',
): Promise<SchemaObjectRow[]> {
  return database.getAllAsync<SchemaObjectRow>(
    `SELECT type, name, tbl_name, sql FROM "${schema}".sqlite_schema
     WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name`,
  );
}

async function requireOrdinaryArchiveTables(database: ArchiveSqlDatabase): Promise<void> {
  const objects = await schemaObjects(database, 'source_archive');
  const byName = new Map(objects.map((object) => [object.name, object]));
  for (const table of [...ARCHIVE_TABLES, 'taisa_archive_manifest'] as const) {
    const object = byName.get(table);
    if (object?.type !== 'table'
      || object.tbl_name !== table
      || object.sql?.trimStart().toUpperCase().startsWith('CREATE VIRTUAL TABLE')) {
      throw new Error('Archive object does not match the trusted schema');
    }
  }
}

async function requireTrustedSchemaIdentity(
  source: ArchiveSqlDatabase,
  candidate: ArchiveSqlDatabase,
): Promise<void> {
  const [sourceObjects, trustedObjects] = await Promise.all([
    schemaObjects(source, 'source_archive'),
    schemaObjects(candidate, 'main'),
  ]);
  const sourceComparable = sourceObjects.filter((object) => object.name !== 'taisa_archive_manifest');
  if (sourceComparable.length !== trustedObjects.length) {
    throw new Error('Archive object set does not match the trusted schema');
  }
  for (let index = 0; index < trustedObjects.length; index += 1) {
    const sourceObject = sourceComparable[index];
    const trustedObject = trustedObjects[index];
    if (sourceObject.type !== trustedObject.type
      || sourceObject.name !== trustedObject.name
      || sourceObject.tbl_name !== trustedObject.tbl_name
      || !schemaSqlMatchesExactly(sourceObject.sql, trustedObject.sql)) {
      throw new Error('Archive object identity does not match the trusted schema');
    }
  }
}

function quoteTrustedIdentifier(identifier: string): string {
  if (!/^[a-z_][a-z0-9_]*$/.test(identifier)) {
    throw new Error('Trusted schema contains an unsupported identifier');
  }
  return `"${identifier}"`;
}

async function tableInfo(
  database: ArchiveSqlDatabase,
  schema: 'main' | 'source_archive',
  table: ArchiveTable,
): Promise<TableInfoRow[]> {
  return database.getAllAsync<TableInfoRow>(
    `PRAGMA ${schema}.table_info(${quoteTrustedIdentifier(table)})`,
  );
}

function sameMappedColumns(source: readonly TableInfoRow[], trusted: readonly TableInfoRow[]): boolean {
  if (source.length === 0 || source.length !== trusted.length) return false;
  return source.every((column, index) => {
    const expected = trusted[index];
    return column.cid === expected.cid
      && column.name === expected.name
      && column.type.toUpperCase() === expected.type.toUpperCase()
      && column.notnull === expected.notnull
      && column.dflt_value === expected.dflt_value
      && column.pk === expected.pk;
  });
}

function bindableRowValue(value: unknown): string | number | null | Uint8Array {
  if (value === null || typeof value === 'string' || typeof value === 'number'
    || value instanceof Uint8Array) return value;
  throw new Error('Archive row contains an unsupported value');
}

async function importAllowlistedTables(
  source: ArchiveSqlDatabase,
  candidate: ArchiveSqlDatabase,
): Promise<void> {
  await candidate.execAsync('BEGIN IMMEDIATE');
  try {
    await candidate.execAsync('PRAGMA defer_foreign_keys = ON');
    await requireTrustedSchemaIdentity(source, candidate);
    for (const table of ARCHIVE_TABLES) {
      const [sourceColumns, trustedColumns] = await Promise.all([
        tableInfo(source, 'source_archive', table),
        tableInfo(candidate, 'main', table),
      ]);
      if (!sameMappedColumns(sourceColumns, trustedColumns)) {
        throw new Error('Archive table mapping does not match the trusted schema');
      }
      const columnSql = trustedColumns
        .map((column) => quoteTrustedIdentifier(column.name))
        .join(', ');
      const rows = await source.getAllAsync<Record<string, unknown>>(
        `SELECT ${columnSql} FROM ${qualified('source_archive', table)}
         ORDER BY ${quoteTrustedIdentifier(TABLE_ORDER_COLUMNS[table])}`,
      );
      const placeholders = trustedColumns.map(() => '?').join(', ');
      for (const row of rows) {
        await candidate.runAsync(
          `INSERT INTO ${quoteTrustedIdentifier(table)} (${columnSql}) VALUES (${placeholders})`,
          trustedColumns.map((column) => bindableRowValue(row[column.name])),
        );
      }
    }
    const foreignKeyFailures = await candidate.getAllAsync<Record<string, unknown>>(
      'PRAGMA foreign_key_check',
    );
    if (foreignKeyFailures.length !== 0) {
      throw new Error('Trusted candidate foreign key verification failed');
    }
    await candidate.execAsync('COMMIT');
  } catch (error) {
    await candidate.execAsync('ROLLBACK');
    throw error;
  }
}

export function createSqlCipherArchiveBoundary(
  dependencies: SqlCipherEngineDependencies,
): SqlCipherArchiveBoundary {
  return {
    async assertExportable() {
      const database = await dependencies.openActive();
      const pendingVoice = await database.getFirstAsync<{ id: string }>(
        `SELECT id FROM coaching_requests
         WHERE audio_uri IS NOT NULL
           AND status NOT IN ('completed', 'abandoned')
         LIMIT 1`,
      );
      if (pendingVoice !== null) {
        throw new ArchiveOperationError('PENDING_VOICE_NOT_BACKED_UP');
      }
    },
    async exportPassphraseArchive({ destinationUri, passphrase }) {
      const database = await dependencies.openActive();
      await database.execAsync('PRAGMA temp_store = MEMORY');
      const snapshot = await fingerprintSchema(database, 'main', dependencies.sha256);
      let attached = false;
      try {
        await attachWithPassphrase(database, destinationUri, 'passphrase_export', passphrase);
        attached = true;
        await database.getFirstAsync(
          `SELECT sqlcipher_export('passphrase_export') AS exported`,
        );
        await database.execAsync(
          `PRAGMA passphrase_export.user_version = ${SCHEMA_VERSION}`,
        );
        await database.execAsync(
          `CREATE TABLE ${qualified('passphrase_export', 'taisa_archive_manifest')} (
            id INTEGER PRIMARY KEY NOT NULL CHECK (id = 1),
            archive_format_version INTEGER NOT NULL,
            schema_version INTEGER NOT NULL,
            counts_json TEXT NOT NULL,
            content_hash TEXT NOT NULL CHECK (
              length(content_hash) = 64 AND content_hash NOT GLOB '*[^0-9a-f]*'
            ),
            created_at TEXT NOT NULL
          )`,
        );
        await database.runAsync(
          `INSERT INTO ${qualified('passphrase_export', 'taisa_archive_manifest')}
            (id, archive_format_version, schema_version, counts_json, content_hash, created_at)
           VALUES (1, ?, ?, ?, ?, ?)`,
          [
            ARCHIVE_FORMAT_VERSION,
            snapshot.schemaVersion,
            JSON.stringify(snapshot.counts),
            snapshot.contentHash,
            new Date().toISOString(),
          ],
        );
        const verified = await inspectAttachedArchive(
          database,
          'passphrase_export',
          dependencies.sha256,
        );
        if (!snapshotsMatch(snapshot, verified)) throw new Error('Export verification failed');
        return verified;
      } finally {
        if (attached) await database.execAsync('DETACH DATABASE passphrase_export');
      }
    },

    async inspectPassphraseArchive({ sourceUri, passphrase }) {
      return withMaintenanceDatabase(dependencies, async (database) => {
        let attached = false;
        try {
          await database.execAsync('PRAGMA trusted_schema = OFF');
          await attachWithPassphrase(database, sourceUri, 'source_archive', passphrase);
          attached = true;
          await requireOrdinaryArchiveTables(database);
          // This is deliberately only a non-executing preliminary inspection. SQLite integrity
          // checks may invoke virtual-table xIntegrity implementations, so content/hash/integrity
          // verification waits until candidate creation has proven exact schema identity against
          // a locally generated trusted schema.
          return readAttachedArchiveManifest(database, 'source_archive');
        } finally {
          if (attached) await detachQuietly(database, 'source_archive');
        }
      });
    },

    async createDeviceEncryptedCandidate({ sourceUri, destinationUri, passphrase }) {
      return withMaintenanceDatabase(dependencies, async (database) => {
        let sourceAttached = false;
        let candidate: ArchiveSqlDatabase | null = null;
        try {
          await database.execAsync('PRAGMA trusted_schema = OFF');
          await attachWithPassphrase(database, sourceUri, 'source_archive', passphrase);
          sourceAttached = true;
          await requireOrdinaryArchiveTables(database);
          const sourceManifest = await readAttachedArchiveManifest(database, 'source_archive');
          if (sourceManifest.schemaVersion < 1 || sourceManifest.schemaVersion > SCHEMA_VERSION) {
            throw new Error('Archive schema version is unsupported');
          }
          const deviceKey = (await dependencies.readDeviceKey()).toLowerCase();
          if (!DEVICE_KEY_PATTERN.test(deviceKey)) throw new Error('Device key is unavailable');
          // The device key is used only to initialize a fresh trusted current-schema database.
          // No sqlite_master SQL, trigger, index, constraint, or other schema object is copied
          // from the selected archive.
          candidate = await dependencies.openDeviceCandidate({
            destinationUri,
            deviceKey,
            schemaVersion: sourceManifest.schemaVersion,
          });
          await requireTrustedSchemaIdentity(database, candidate);
          const sourceSnapshot = await inspectAttachedArchive(
            database,
            'source_archive',
            dependencies.sha256,
            { manifest: sourceManifest, verifySearchIndexes: false },
          );
          // After FTS integrity and schema identity checks, the maintenance connection becomes
          // strictly source-only for the bound-value copy.
          await database.execAsync('PRAGMA query_only = ON');
          await importAllowlistedTables(database, candidate);
          const importedSnapshot = await fingerprintSchema(
            candidate,
            'main',
            dependencies.sha256,
          );
          if (!snapshotsMatch(sourceSnapshot, importedSnapshot)) {
            throw new Error('Trusted device candidate verification failed');
          }
          if (sourceSnapshot.schemaVersion < SCHEMA_VERSION) {
            await runMigrations(candidate);
          }
          const candidateSnapshot = await fingerprintSchema(
            candidate,
            'main',
            dependencies.sha256,
          );
          if (!candidateMatchesVerifiedSource(sourceSnapshot, candidateSnapshot)) {
            throw new Error('Migrated device candidate verification failed');
          }
          return candidateSnapshot;
        } finally {
          if (candidate !== null) await candidate.closeAsync();
          if (sourceAttached) await detachQuietly(database, 'source_archive');
        }
      });
    },

    async checkpointActive() {
      const database = await dependencies.openActive();
      await database.execAsync('PRAGMA wal_checkpoint(TRUNCATE)');
    },

    async fingerprintActive() {
      const database = await dependencies.openActive();
      await database.execAsync('PRAGMA temp_store = MEMORY');
      return fingerprintSchema(database, 'main', dependencies.sha256);
    },
  };
}

const nativeSqlCipherBoundary = createSqlCipherArchiveBoundary({
  openActive: openTaisaDatabase,
  openMaintenance: () => SQLite.openDatabaseAsync(MAINTENANCE_DATABASE_NAME),
  async openDeviceCandidate({ destinationUri, deviceKey, schemaVersion }) {
    const directory = SQLite.defaultDatabaseDirectory;
    if (typeof directory !== 'string' || directory.length === 0) {
      throw new Error('SQLite database directory is unavailable on this platform');
    }
    const expectedUri = new File(directory, RESTORE_CANDIDATE_NAME).uri;
    if (destinationUri !== expectedUri) throw new Error('Candidate archive path is invalid');
    const database = await SQLite.openDatabaseAsync(RESTORE_CANDIDATE_NAME);
    try {
      await database.execAsync(`PRAGMA key = "x'${deviceKey}'"`);
      await requireSqlCipher(database);
      await database.execAsync('PRAGMA foreign_keys = ON');
      await database.execAsync('PRAGMA journal_mode = DELETE');
      await runMigrations(database, schemaVersion);
      return database;
    } catch (error) {
      await database.closeAsync();
      throw error;
    }
  },
  async deleteMaintenance() {
    await SQLite.deleteDatabaseAsync(MAINTENANCE_DATABASE_NAME);
  },
  async readDeviceKey() {
    const key = await SecureStore.getItemAsync(DEVICE_KEY_NAME);
    if (key === null) throw new Error('Device database key is unavailable');
    return key;
  },
  async sha256(input) {
    return Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, input);
  },
});

const defaultArchiveService = createEncryptedArchiveService({
  files: createExpoArchiveFileBoundary(),
  sqlCipher: nativeSqlCipherBoundary,
  lifecycle: {
    withMaintenance: withTaisaMaintenance,
    async invalidateClients() {
      invalidateLocalCaptureService();
    },
    close: closeTaisaDatabase,
    async reopen() {
      await openTaisaDatabase();
    },
  },
});

export function exportEncryptedArchive(
  passphrase: string,
  confirmation: string,
): Promise<{ uri: string; snapshot: ArchiveSnapshot }> {
  return defaultArchiveService.exportEncryptedArchive(
    confirmArchivePassphrase(passphrase, confirmation),
  );
}

export function restoreEncryptedArchive(
  uri: string,
  passphrase: string,
): Promise<{ snapshot: ArchiveSnapshot }> {
  return defaultArchiveService.restoreEncryptedArchive(uri, passphrase);
}

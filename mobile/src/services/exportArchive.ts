import * as Crypto from 'expo-crypto';
import * as SecureStore from 'expo-secure-store';
import * as SQLite from 'expo-sqlite';
import type { SQLiteDatabase } from 'expo-sqlite';

import { SCHEMA_VERSION } from '../db/migrations';
import { closeTaisaDatabase, openTaisaDatabase } from '../db/openDatabase';
import { invalidateLocalCaptureService } from './localPlatform';
import {
  ACTIVE_DATABASE_NAME,
  createExpoArchiveFileBoundary,
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

function requireSupportedSnapshot(snapshot: ArchiveSnapshot): void {
  if (snapshot.archiveFormatVersion !== ARCHIVE_FORMAT_VERSION
    || snapshot.schemaVersion !== SCHEMA_VERSION) {
    throw new ArchiveOperationError('UNSUPPORTED_ARCHIVE_VERSION');
  }
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
      return exclusively(async () => {
        if (confirmedPassphrase.confirmed !== true) {
          throw new ArchiveOperationError('PASSPHRASE_CONFIRMATION_MISMATCH');
        }
        validatePassphrase(confirmedPassphrase.value);
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
          requireSupportedSnapshot(snapshot);
          return { uri: destinationUri, snapshot };
        } catch (cause) {
          await dependencies.files.discardExport?.(destinationUri);
          if (cause instanceof ArchiveOperationError) throw cause;
          throw new ArchiveOperationError('ARCHIVE_VERIFICATION_FAILED');
        }
      });
    },

    async restoreEncryptedArchive(uri, passphrase) {
      return exclusively(async () => {
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
          requireSupportedSnapshot(sourceSnapshot);

          candidateUri = dependencies.files.createCandidateUri();
          const candidateSnapshot = await dependencies.sqlCipher.createDeviceEncryptedCandidate({
            sourceUri: stagedUri,
            destinationUri: candidateUri,
            passphrase,
          });
          if (!snapshotsMatch(sourceSnapshot, candidateSnapshot)) {
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
            if (promotedDatabaseOpen) {
              await dependencies.lifecycle.close();
              promotedDatabaseOpen = false;
            }
            await dependencies.files.rollbackPromotion();
            await dependencies.lifecycle.reopen();
            activeClosed = false;
          } else if (activeClosed) {
            await dependencies.lifecycle.reopen();
            activeClosed = false;
          }

          if (cause instanceof ArchiveOperationError) throw cause;
          throw new ArchiveOperationError('RESTORE_FAILED');
        } finally {
          await dependencies.files.cleanupTemporaryFiles();
          void stagedUri;
          void candidateUri;
        }
      });
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

  const counts = {} as ArchiveEntityCounts;
  const canonicalTables: unknown[] = [];
  for (const table of ARCHIVE_TABLES) {
    const rows = await database.getAllAsync<Record<string, unknown>>(
      `SELECT * FROM ${qualified(schema, table)} ORDER BY "${TABLE_ORDER_COLUMNS[table]}"`,
    );
    counts[table] = rows.length;
    canonicalTables.push([table, rows]);
  }

  const missingMessageIndex = await database.getFirstAsync<{ id: string }>(
    `SELECT messages.id AS id FROM ${qualified(schema, 'messages')} AS messages
     LEFT JOIN ${qualified(schema, 'message_search')} AS search ON search.rowid = messages.rowid
     WHERE search.rowid IS NULL OR search.content != messages.content LIMIT 1`,
  );
  const missingEvidenceIndex = await database.getFirstAsync<{ id: string }>(
    `SELECT evidence.id AS id FROM ${qualified(schema, 'evidence')} AS evidence
     LEFT JOIN ${qualified(schema, 'evidence_search')} AS search ON search.rowid = evidence.rowid
     WHERE search.rowid IS NULL OR search.statement != evidence.statement LIMIT 1`,
  );
  if (missingMessageIndex !== null || missingEvidenceIndex !== null) {
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
  const manifest = parseArchiveManifestForValidation(manifestRow);
  if (manifest.schemaVersion !== SCHEMA_VERSION) return manifest;
  const actual = await fingerprintSchema(database, schema, sha256);
  if (!snapshotsMatch(manifest, actual)) throw new Error('Archive fingerprint does not match');
  return actual;
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

export function createSqlCipherArchiveBoundary(
  dependencies: SqlCipherEngineDependencies,
): SqlCipherArchiveBoundary {
  return {
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
          await attachWithPassphrase(database, sourceUri, 'source_archive', passphrase);
          attached = true;
          return await inspectAttachedArchive(database, 'source_archive', dependencies.sha256);
        } finally {
          if (attached) await detachQuietly(database, 'source_archive');
        }
      });
    },

    async createDeviceEncryptedCandidate({ sourceUri, destinationUri, passphrase }) {
      return withMaintenanceDatabase(dependencies, async (database) => {
        let sourceAttached = false;
        let candidateAttached = false;
        try {
          await attachWithPassphrase(database, sourceUri, 'source_archive', passphrase);
          sourceAttached = true;
          const sourceSnapshot = await inspectAttachedArchive(
            database,
            'source_archive',
            dependencies.sha256,
          );
          const deviceKey = (await dependencies.readDeviceKey()).toLowerCase();
          if (!DEVICE_KEY_PATTERN.test(deviceKey)) throw new Error('Device key is unavailable');
          // The key is a validated fixed-size hexadecimal value. It encrypts only the local
          // candidate and is never used for, written to, or returned with the backup archive.
          await database.runAsync(
            `ATTACH DATABASE ? AS device_candidate KEY "x'${deviceKey}'"`,
            [destinationUri],
          );
          candidateAttached = true;
          await database.getFirstAsync(
            `SELECT sqlcipher_export('device_candidate', 'source_archive') AS exported`,
          );
          const archivedCandidateSnapshot = await inspectAttachedArchive(
            database,
            'device_candidate',
            dependencies.sha256,
          );
          if (!snapshotsMatch(sourceSnapshot, archivedCandidateSnapshot)) {
            throw new Error('Device candidate verification failed');
          }

          // The manifest belongs only to the passphrase-encrypted backup. Keeping it in the
          // promoted application database would make a later export collide with the old manifest.
          await database.execAsync(
            `DROP TABLE ${qualified('device_candidate', 'taisa_archive_manifest')}`,
          );
          const candidateSnapshot = await fingerprintSchema(
            database,
            'device_candidate',
            dependencies.sha256,
          );
          if (!snapshotsMatch(sourceSnapshot, candidateSnapshot)) {
            throw new Error('Device candidate changed while removing its backup manifest');
          }
          return candidateSnapshot;
        } finally {
          if (candidateAttached) await detachQuietly(database, 'device_candidate');
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

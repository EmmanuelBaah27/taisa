import { Directory, File, Paths } from 'expo-file-system';
import * as SQLite from 'expo-sqlite';

export const ACTIVE_DATABASE_NAME = 'taisa-local.db';
const RESTORE_INPUT_NAME = 'taisa-restore-input.db';
const RESTORE_CANDIDATE_NAME = 'taisa-restore-candidate.db';
const RESTORE_ROLLBACK_NAME = 'taisa-restore-original.db';
const RESTORE_MARKER_NAME = 'taisa-restore-pending.marker';

export interface ArchiveFileBoundary {
  availableDiskSpace(): Promise<number>;
  size(uri: string): Promise<number>;
  createExportUri(): string;
  discardExport?(uri: string): Promise<void>;
  stageSelectedArchive(sourceUri: string): Promise<string>;
  createCandidateUri(): string;
  preparePromotion(): Promise<void>;
  promoteCandidate(): Promise<void>;
  rollbackPromotion(): Promise<void>;
  commitPromotion(): Promise<void>;
  cleanupTemporaryFiles(): Promise<void>;
}

function databaseDirectory(): string {
  if (typeof SQLite.defaultDatabaseDirectory !== 'string'
    || SQLite.defaultDatabaseDirectory.length === 0) {
    throw new Error('SQLite database directory is unavailable on this platform');
  }
  return SQLite.defaultDatabaseDirectory;
}

function databaseFile(name: string): File {
  return new File(databaseDirectory(), name);
}

function deleteIfPresent(file: File): void {
  if (file.exists) file.delete();
}

function clearDatabaseSidecars(name: string): void {
  for (const suffix of ['-wal', '-shm']) {
    const sidecar = databaseFile(`${name}${suffix}`);
    if (!sidecar.exists) continue;
    if ((sidecar.size ?? 0) > 0) {
      throw new Error('Database sidecar was not checkpointed before recovery');
    }
    sidecar.delete();
  }
}

function fixedRestoreFiles() {
  return {
    active: databaseFile(ACTIVE_DATABASE_NAME),
    input: databaseFile(RESTORE_INPUT_NAME),
    candidate: databaseFile(RESTORE_CANDIDATE_NAME),
    rollback: databaseFile(RESTORE_ROLLBACK_NAME),
    marker: databaseFile(RESTORE_MARKER_NAME),
  };
}

/**
 * Runs before the encrypted database is opened. A marker always means promotion was not
 * committed, so the preserved original wins. Repeating this recovery is safe after interruption.
 */
export async function recoverInterruptedArchivePromotion(): Promise<void> {
  const files = fixedRestoreFiles();
  if (!files.marker.exists) return;
  if (!files.rollback.exists) {
    throw new Error('Interrupted restore is missing its preserved original database');
  }

  clearDatabaseSidecars(ACTIVE_DATABASE_NAME);
  deleteIfPresent(files.active);
  files.rollback.copy(files.active);
  deleteIfPresent(files.input);
  deleteIfPresent(files.candidate);
  deleteIfPresent(files.rollback);
  deleteIfPresent(files.marker);
}

export function createExpoArchiveFileBoundary(): ArchiveFileBoundary {
  return {
    async availableDiskSpace() {
      const value = Paths.availableDiskSpace;
      if (!Number.isSafeInteger(value) || value < 0) {
        throw new Error('Available disk space could not be measured');
      }
      return value;
    },
    async size(uri) {
      const size = (uri === ACTIVE_DATABASE_NAME ? databaseFile(uri) : new File(uri)).size;
      if (typeof size !== 'number' || !Number.isFinite(size) || size < 0) {
        throw new Error('Archive file size could not be measured');
      }
      return size;
    },
    createExportUri() {
      const directory = new Directory(Paths.document, 'taisa-backups');
      directory.create({ idempotent: true, intermediates: true });
      const safeTimestamp = new Date().toISOString().replace(/[:.]/g, '-');
      return new File(directory, `taisa-backup-${safeTimestamp}.sqlite3`).uri;
    },
    async discardExport(uri) {
      deleteIfPresent(new File(uri));
    },
    async stageSelectedArchive(sourceUri) {
      const { input } = fixedRestoreFiles();
      deleteIfPresent(input);
      const source = new File(sourceUri);
      if (!source.exists) throw new Error('Selected archive is unavailable');
      source.copy(input);
      return input.uri;
    },
    createCandidateUri() {
      const { candidate } = fixedRestoreFiles();
      deleteIfPresent(candidate);
      return candidate.uri;
    },
    async preparePromotion() {
      const { active, rollback, marker } = fixedRestoreFiles();
      if (!active.exists) throw new Error('Active encrypted database is unavailable');
      clearDatabaseSidecars(ACTIVE_DATABASE_NAME);
      deleteIfPresent(rollback);
      deleteIfPresent(marker);
      active.copy(rollback);
      marker.create({ overwrite: true, intermediates: true });
      marker.write('restore-pending-v1');
    },
    async promoteCandidate() {
      const { active, candidate, marker, rollback } = fixedRestoreFiles();
      if (!marker.exists || !rollback.exists || !candidate.exists) {
        throw new Error('Restore promotion was not prepared');
      }
      deleteIfPresent(active);
      candidate.move(active);
    },
    async rollbackPromotion() {
      const { active, rollback, marker } = fixedRestoreFiles();
      if (!marker.exists) return;
      if (!rollback.exists) throw new Error('Preserved original database is unavailable');
      clearDatabaseSidecars(ACTIVE_DATABASE_NAME);
      deleteIfPresent(active);
      rollback.copy(active);
    },
    async commitPromotion() {
      const { marker, rollback } = fixedRestoreFiles();
      // Marker removal is the commit point. A leftover rollback after interruption is harmless.
      deleteIfPresent(marker);
      deleteIfPresent(rollback);
    },
    async cleanupTemporaryFiles() {
      const { input, candidate, marker, rollback } = fixedRestoreFiles();
      deleteIfPresent(input);
      deleteIfPresent(candidate);
      // A pending marker owns the rollback and startup recovery must retain both.
      if (!marker.exists) deleteIfPresent(rollback);
    },
  };
}

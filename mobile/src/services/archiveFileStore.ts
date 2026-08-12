import * as Crypto from 'expo-crypto';
import { Directory, File, Paths } from 'expo-file-system';
import * as SQLite from 'expo-sqlite';

export const ACTIVE_DATABASE_NAME = 'taisa-local.db';
const RESTORE_INPUT_NAME = 'taisa-restore-input.db';
export const RESTORE_CANDIDATE_NAME = 'taisa-restore-candidate.db';
const RESTORE_ROLLBACK_NAME = 'taisa-restore-original.db';
const RESTORE_MARKER_NAME = 'taisa-restore-pending.marker';
const RESTORE_MARKER_TEMP_NAME = 'taisa-restore-pending.marker.tmp';

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

interface ExportReservationBoundary {
  createExclusive(name: string): string;
  randomUUID(): string;
}

export function createReservedExportUri(boundary: ExportReservationBoundary): string {
  const uuid = boundary.randomUUID();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(uuid)) {
    throw new Error('A secure export identifier is unavailable');
  }
  return boundary.createExclusive(`taisa-backup-${uuid}.sqlite3`);
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

function discardDatabaseSidecars(name: string): void {
  for (const suffix of ['-wal', '-shm']) deleteIfPresent(databaseFile(`${name}${suffix}`));
}

function fixedRestoreFiles() {
  return {
    active: databaseFile(ACTIVE_DATABASE_NAME),
    input: databaseFile(RESTORE_INPUT_NAME),
    candidate: databaseFile(RESTORE_CANDIDATE_NAME),
    rollback: databaseFile(RESTORE_ROLLBACK_NAME),
    marker: databaseFile(RESTORE_MARKER_NAME),
    markerTemp: databaseFile(RESTORE_MARKER_TEMP_NAME),
  };
}

interface PromotionMarkerV1 {
  readonly version: 1;
  readonly state: 'prepared';
  readonly restoreId: string;
  readonly originalSize: number;
  readonly originalDigest: string;
}

export interface PromotionRecoveryFileBoundary {
  readMarker(): Promise<string | null>;
  inspect(target: 'active' | 'rollback'): Promise<{ size: number; digest: string } | null>;
  discardUncommittedActive(): Promise<void>;
  copyRollbackToActive(): Promise<void>;
  removeMarker(): Promise<void>;
  removeRollback(): Promise<void>;
  cleanupStaleArtifacts(): Promise<void>;
}

export interface PromotionMarkerPublicationBoundary {
  readonly finalPath: string;
  createExclusiveTemp(): string;
  writeTemp(path: string, value: string): void;
  publishTemp(tempPath: string, finalPath: string): void;
}

export async function publishPromotionMarker(
  files: PromotionMarkerPublicationBoundary,
  value: string,
): Promise<void> {
  const tempPath = files.createExclusiveTemp();
  files.writeTemp(tempPath, value);
  files.publishTemp(tempPath, files.finalPath);
}

function parsePromotionMarker(value: string): PromotionMarkerV1 {
  const parsed = JSON.parse(value) as Partial<PromotionMarkerV1>;
  if (parsed.version !== 1
    || parsed.state !== 'prepared'
    || typeof parsed.restoreId !== 'string'
    || !/^[0-9a-f-]{36}$/i.test(parsed.restoreId)
    || !Number.isSafeInteger(parsed.originalSize)
    || (parsed.originalSize ?? -1) < 0
    || typeof parsed.originalDigest !== 'string'
    || !/^[0-9a-f]{32,64}$/i.test(parsed.originalDigest)) {
    throw new Error('Restore marker is invalid');
  }
  return parsed as PromotionMarkerV1;
}

function fileIdentity(file: File): { size: number; digest: string } | null {
  if (!file.exists) return null;
  const info = file.info({ md5: true });
  if (typeof info.size !== 'number' || !Number.isFinite(info.size) || info.size < 0
    || typeof info.md5 !== 'string' || !/^[0-9a-f]{32}$/i.test(info.md5)) {
    throw new Error('Archive file identity could not be measured');
  }
  return { size: info.size, digest: info.md5.toLowerCase() };
}

function identitiesMatch(
  marker: PromotionMarkerV1,
  identity: { size: number; digest: string },
): boolean {
  return marker.originalSize === identity.size
    && marker.originalDigest.toLowerCase() === identity.digest.toLowerCase();
}

/**
 * Marker presence means the candidate never committed. Every mutating step is repeatable: the
 * preserved original is copied (not consumed), verified in place, and retained until marker
 * removal commits recovery. A later startup cleans harmless leftovers after that commit point.
 */
export async function recoverArchivePromotion(
  files: PromotionRecoveryFileBoundary,
): Promise<void> {
  const markerText = await files.readMarker();
  if (markerText === null) {
    await files.cleanupStaleArtifacts();
    return;
  }
  let marker: PromotionMarkerV1;
  try {
    marker = parsePromotionMarker(markerText);
  } catch {
    if (markerText === 'restore-pending-v1') {
      const rollback = await files.inspect('rollback');
      if (rollback === null) {
        throw new Error('Legacy restore marker has no preserved original database');
      }
      marker = {
        version: 1,
        state: 'prepared',
        restoreId: '00000000-0000-4000-8000-000000000000',
        originalSize: rollback.size,
        originalDigest: rollback.digest,
      };
    } else if (markerText.trim() === '') {
      // Older interrupted builds could expose an empty/truncated JSON final marker before
      // promotion. With no complete marker, the active database remains authoritative.
      await files.removeMarker();
      await files.cleanupStaleArtifacts();
      return;
    } else {
      try {
        JSON.parse(markerText);
      } catch {
        if (markerText.trimStart().startsWith('{')) {
          await files.removeMarker();
          await files.cleanupStaleArtifacts();
          return;
        }
      }
      // An unknown complete marker may describe a promotion protocol we cannot safely infer.
      throw new Error('Restore marker is invalid');
    }
  }
  const rollback = await files.inspect('rollback');
  if (rollback === null || !identitiesMatch(marker, rollback)) {
    throw new Error('Restore marker does not match the preserved original database');
  }

  await files.discardUncommittedActive();
  await files.copyRollbackToActive();
  const restored = await files.inspect('active');
  if (restored === null || !identitiesMatch(marker, restored)) {
    throw new Error('Restored original database did not match its recovery marker');
  }
  await files.removeMarker();
  await files.removeRollback();
  await files.cleanupStaleArtifacts();
}

function createExpoPromotionRecoveryBoundary(): PromotionRecoveryFileBoundary {
  return {
    async readMarker() {
      const { marker } = fixedRestoreFiles();
      return marker.exists ? marker.textSync() : null;
    },
    async inspect(target) {
      const files = fixedRestoreFiles();
      return fileIdentity(target === 'active' ? files.active : files.rollback);
    },
    async discardUncommittedActive() {
      const { active } = fixedRestoreFiles();
      discardDatabaseSidecars(ACTIVE_DATABASE_NAME);
      deleteIfPresent(active);
    },
    async copyRollbackToActive() {
      const { active, rollback } = fixedRestoreFiles();
      if (!rollback.exists) throw new Error('Preserved original database is unavailable');
      deleteIfPresent(active);
      rollback.copy(active);
    },
    async removeMarker() {
      deleteIfPresent(fixedRestoreFiles().marker);
    },
    async removeRollback() {
      deleteIfPresent(fixedRestoreFiles().rollback);
    },
    async cleanupStaleArtifacts() {
      const { input, candidate, rollback, markerTemp } = fixedRestoreFiles();
      deleteIfPresent(input);
      discardDatabaseSidecars(RESTORE_INPUT_NAME);
      deleteIfPresent(candidate);
      discardDatabaseSidecars(RESTORE_CANDIDATE_NAME);
      deleteIfPresent(rollback);
      deleteIfPresent(markerTemp);
    },
  };
}

/**
 * Runs before the encrypted database is opened. A marker always means promotion was not
 * committed, so the preserved original wins. Repeating this recovery is safe after interruption.
 */
export async function recoverInterruptedArchivePromotion(): Promise<void> {
  await recoverArchivePromotion(createExpoPromotionRecoveryBoundary());
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
      return createReservedExportUri({
        randomUUID: Crypto.randomUUID,
        createExclusive(name) {
          const destination = new File(directory, name);
          destination.create({ overwrite: false, intermediates: true });
          return destination.uri;
        },
      });
    },
    async discardExport(uri) {
      deleteIfPresent(new File(uri));
    },
    async stageSelectedArchive(sourceUri) {
      const { input } = fixedRestoreFiles();
      discardDatabaseSidecars(RESTORE_INPUT_NAME);
      deleteIfPresent(input);
      const source = new File(sourceUri);
      if (!source.exists) throw new Error('Selected archive is unavailable');
      source.copy(input);
      return input.uri;
    },
    createCandidateUri() {
      const { candidate } = fixedRestoreFiles();
      discardDatabaseSidecars(RESTORE_CANDIDATE_NAME);
      deleteIfPresent(candidate);
      return candidate.uri;
    },
    async preparePromotion() {
      const { active, rollback, marker, markerTemp } = fixedRestoreFiles();
      if (!active.exists) throw new Error('Active encrypted database is unavailable');
      clearDatabaseSidecars(ACTIVE_DATABASE_NAME);
      deleteIfPresent(rollback);
      deleteIfPresent(marker);
      deleteIfPresent(markerTemp);
      active.copy(rollback);
      const [originalIdentity, rollbackIdentity] = [fileIdentity(active), fileIdentity(rollback)];
      if (originalIdentity === null || rollbackIdentity === null
        || originalIdentity.size !== rollbackIdentity.size
        || originalIdentity.digest !== rollbackIdentity.digest) {
        throw new Error('Preserved original database could not be verified');
      }
      const promotionMarker: PromotionMarkerV1 = {
        version: 1,
        state: 'prepared',
        restoreId: Crypto.randomUUID(),
        originalSize: rollbackIdentity.size,
        originalDigest: rollbackIdentity.digest,
      };
      await publishPromotionMarker({
        finalPath: marker.uri,
        createExclusiveTemp() {
          markerTemp.create({ overwrite: false, intermediates: true });
          return markerTemp.uri;
        },
        writeTemp(path, value) {
          if (path !== markerTemp.uri) throw new Error('Restore marker temp path is invalid');
          markerTemp.write(value);
        },
        publishTemp(tempPath, finalPath) {
          if (tempPath !== markerTemp.uri || finalPath !== marker.uri) {
            throw new Error('Restore marker publication path is invalid');
          }
          markerTemp.move(marker);
        },
      }, JSON.stringify(promotionMarker));
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
      await recoverArchivePromotion(createExpoPromotionRecoveryBoundary());
    },
    async commitPromotion() {
      const { marker } = fixedRestoreFiles();
      // Marker removal is the only commit step. A leftover rollback is harmless and startup
      // cleanup can remove it without ever mistaking a committed candidate for an interruption.
      deleteIfPresent(marker);
    },
    async cleanupTemporaryFiles() {
      const { input, candidate, marker, markerTemp, rollback } = fixedRestoreFiles();
      deleteIfPresent(input);
      discardDatabaseSidecars(RESTORE_INPUT_NAME);
      deleteIfPresent(candidate);
      discardDatabaseSidecars(RESTORE_CANDIDATE_NAME);
      deleteIfPresent(markerTemp);
      // A pending marker owns the rollback and startup recovery must retain both.
      if (!marker.exists) deleteIfPresent(rollback);
    },
  };
}

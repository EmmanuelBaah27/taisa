import { createHash } from 'crypto';
import {
  mkdtempSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
  copyFileSync,
  closeSync,
  existsSync,
  openSync,
  renameSync,
} from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';

import {
  createReservedExportUri,
  recoverArchivePromotion,
  publishPromotionMarker,
  type PromotionRecoveryFileBoundary,
} from '../archiveFileStore';

const ORIGINAL = 'encrypted-original-database';
const CANDIDATE = 'uncommitted-candidate-database';

function digest(path: string): string {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

function makeRealFileBoundary(interruptAfter?: string) {
  const directory = mkdtempSync(join(tmpdir(), 'taisa-recovery-'));
  const paths = {
    active: join(directory, 'active.db'),
    rollback: join(directory, 'rollback.db'),
    marker: join(directory, 'pending.marker'),
    input: join(directory, 'input.db'),
    candidate: join(directory, 'candidate.db'),
    activeWal: join(directory, 'active.db-wal'),
    activeShm: join(directory, 'active.db-shm'),
    candidateWal: join(directory, 'candidate.db-wal'),
    candidateShm: join(directory, 'candidate.db-shm'),
  };
  writeFileSync(paths.active, CANDIDATE);
  writeFileSync(paths.rollback, ORIGINAL);
  writeFileSync(paths.input, 'passphrase-encrypted-input');
  writeFileSync(paths.candidate, 'stale-candidate-copy');
  writeFileSync(paths.activeWal, 'non-empty candidate WAL');
  writeFileSync(paths.activeShm, 'non-empty candidate SHM');
  writeFileSync(paths.candidateWal, 'candidate WAL');
  writeFileSync(paths.candidateShm, 'candidate SHM');
  const originalStat = statSync(paths.rollback);
  writeFileSync(paths.marker, JSON.stringify({
    version: 1,
    state: 'prepared',
    restoreId: '123e4567-e89b-42d3-a456-426614174000',
    originalSize: originalStat.size,
    originalDigest: digest(paths.rollback),
  }));

  let didInterrupt = false;
  function checkpoint(name: string): void {
    if (!didInterrupt && interruptAfter === name) {
      didInterrupt = true;
      throw new Error(`interrupted-after-${name}`);
    }
  }
  function deleteIfPresent(path: string): void {
    if (existsSync(path)) rmSync(path);
  }

  const boundary: PromotionRecoveryFileBoundary = {
    readMarker: async () => existsSync(paths.marker) ? readFileSync(paths.marker, 'utf8') : null,
    inspect: async (target) => {
      const path = target === 'active' ? paths.active : paths.rollback;
      return existsSync(path) ? { size: statSync(path).size, digest: digest(path) } : null;
    },
    async discardUncommittedActive() {
      deleteIfPresent(paths.activeWal);
      deleteIfPresent(paths.activeShm);
      deleteIfPresent(paths.active);
      checkpoint('discard-active');
    },
    async copyRollbackToActive() {
      copyFileSync(paths.rollback, paths.active);
      checkpoint('copy-original');
    },
    async removeMarker() {
      deleteIfPresent(paths.marker);
      checkpoint('remove-marker');
    },
    async removeRollback() {
      deleteIfPresent(paths.rollback);
      checkpoint('remove-rollback');
    },
    async cleanupStaleArtifacts() {
      for (const path of [
        paths.input,
        paths.candidate,
        paths.candidateWal,
        paths.candidateShm,
        paths.rollback,
      ]) deleteIfPresent(path);
      checkpoint('cleanup-stale');
    },
  };

  return { boundary, directory, paths };
}

describe('archive promotion startup recovery', () => {
  test.each(['', '{"version":1'])('cleans an unpublished partial marker while preserving rollback and active', async (markerText) => {
    const harness = makeRealFileBoundary();
    try {
      writeFileSync(harness.paths.marker, markerText);
      await expect(recoverArchivePromotion(harness.boundary)).resolves.toBeUndefined();
      expect(readFileSync(harness.paths.active, 'utf8')).toBe(CANDIDATE);
      expect(existsSync(harness.paths.marker)).toBe(false);
      expect(existsSync(harness.paths.rollback)).toBe(false);
    } finally {
      rmSync(harness.directory, { recursive: true, force: true });
    }
  });

  test('recovers the preserved original for the complete legacy pending marker', async () => {
    const harness = makeRealFileBoundary();
    try {
      writeFileSync(harness.paths.marker, 'restore-pending-v1');
      await expect(recoverArchivePromotion(harness.boundary)).resolves.toBeUndefined();
      expect(readFileSync(harness.paths.active, 'utf8')).toBe(ORIGINAL);
      expect(existsSync(harness.paths.marker)).toBe(false);
      expect(existsSync(harness.paths.rollback)).toBe(false);
    } finally {
      rmSync(harness.directory, { recursive: true, force: true });
    }
  });

  test('fails closed for an unknown complete marker instead of deleting its rollback', async () => {
    const harness = makeRealFileBoundary();
    try {
      writeFileSync(harness.paths.marker, 'restore-pending-v2');
      await expect(recoverArchivePromotion(harness.boundary)).rejects.toThrow('invalid');
      expect(readFileSync(harness.paths.active, 'utf8')).toBe(CANDIDATE);
      expect(existsSync(harness.paths.marker)).toBe(true);
      expect(existsSync(harness.paths.rollback)).toBe(true);
    } finally {
      rmSync(harness.directory, { recursive: true, force: true });
    }
  });

  test('fails closed for a syntactically complete future JSON marker', async () => {
    const harness = makeRealFileBoundary();
    try {
      writeFileSync(harness.paths.marker, JSON.stringify({ version: 2, state: 'prepared' }));
      await expect(recoverArchivePromotion(harness.boundary)).rejects.toThrow('invalid');
      expect(readFileSync(harness.paths.active, 'utf8')).toBe(CANDIDATE);
      expect(existsSync(harness.paths.marker)).toBe(true);
      expect(existsSync(harness.paths.rollback)).toBe(true);
    } finally {
      rmSync(harness.directory, { recursive: true, force: true });
    }
  });

  test.each([
    'discard-active',
    'copy-original',
    'remove-marker',
    'remove-rollback',
    'cleanup-stale',
  ])('repeated startup converges after interruption at %s', async (interruptAfter) => {
    const harness = makeRealFileBoundary(interruptAfter);
    try {
      await expect(recoverArchivePromotion(harness.boundary)).rejects.toThrow('interrupted');
      await expect(recoverArchivePromotion(harness.boundary)).resolves.toBeUndefined();
      await expect(recoverArchivePromotion(harness.boundary)).resolves.toBeUndefined();

      expect(readFileSync(harness.paths.active, 'utf8')).toBe(ORIGINAL);
      for (const path of [
        harness.paths.marker,
        harness.paths.rollback,
        harness.paths.input,
        harness.paths.candidate,
        harness.paths.activeWal,
        harness.paths.activeShm,
        harness.paths.candidateWal,
        harness.paths.candidateShm,
      ]) expect(existsSync(path)).toBe(false);
    } finally {
      rmSync(harness.directory, { recursive: true, force: true });
    }
  });

  test('does not replace the active database when marker identity does not match the rollback', async () => {
    const harness = makeRealFileBoundary();
    try {
      writeFileSync(harness.paths.rollback, 'wrong-original');
      await expect(recoverArchivePromotion(harness.boundary)).rejects.toThrow('preserved original');
      expect(readFileSync(harness.paths.active, 'utf8')).toBe(CANDIDATE);
      expect(existsSync(harness.paths.marker)).toBe(true);
    } finally {
      rmSync(harness.directory, { recursive: true, force: true });
    }
  });
});

describe('promotion marker publication', () => {
  test('publishes a same-directory temp marker by exclusive create and atomic rename', async () => {
    const directory = mkdtempSync(join(tmpdir(), 'taisa-marker-'));
    const finalPath = join(directory, 'pending.marker');
    const tempPath = join(directory, 'pending.marker.tmp');
    const calls: string[] = [];
    try {
      await publishPromotionMarker({
        createExclusiveTemp() {
          calls.push('create');
          closeSync(openSync(tempPath, 'wx'));
          return tempPath;
        },
        writeTemp(_path, value) {
          calls.push('write');
          writeFileSync(tempPath, value);
        },
        publishTemp(_temp, _final) {
          calls.push('rename');
          renameSync(tempPath, finalPath);
        },
        finalPath,
      }, JSON.stringify({ version: 1 }));

      expect(calls).toEqual(['create', 'write', 'rename']);
      expect(readFileSync(finalPath, 'utf8')).toBe('{"version":1}');
      expect(existsSync(tempPath)).toBe(false);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });

  test.each(['create', 'write', 'rename'])('never exposes a partial final marker when interrupted during %s', async (interruptAt) => {
    const directory = mkdtempSync(join(tmpdir(), 'taisa-marker-interrupt-'));
    const finalPath = join(directory, 'pending.marker');
    const tempPath = join(directory, 'pending.marker.tmp');
    try {
      await expect(publishPromotionMarker({
        createExclusiveTemp() {
          if (interruptAt === 'create') throw new Error('interrupted');
          closeSync(openSync(tempPath, 'wx'));
          return tempPath;
        },
        writeTemp(_path, value) {
          writeFileSync(tempPath, value);
          if (interruptAt === 'write') throw new Error('interrupted');
        },
        publishTemp() {
          if (interruptAt === 'rename') throw new Error('interrupted');
          renameSync(tempPath, finalPath);
        },
        finalPath,
      }, '{"version":1}')).rejects.toThrow('interrupted');
      expect(existsSync(finalPath)).toBe(false);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });
});

describe('archive export reservation', () => {
  test('uses a UUID filename and fails rather than overwriting an existing reservation', () => {
    const directory = mkdtempSync(join(tmpdir(), 'taisa-export-'));
    const uuid = '123e4567-e89b-42d3-a456-426614174000';
    const createExclusive = (name: string): string => {
      const path = join(directory, name);
      closeSync(openSync(path, 'wx'));
      return path;
    };

    try {
      const first = createReservedExportUri({
        createExclusive,
        randomUUID: () => uuid,
      });
      expect(first).toContain(uuid);
      expect(() => createReservedExportUri({
        createExclusive,
        randomUUID: () => uuid,
      })).toThrow();
      expect(readFileSync(first)).toHaveLength(0);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });
});

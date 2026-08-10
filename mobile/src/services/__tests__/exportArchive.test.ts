import {
  ArchiveOperationError,
  confirmArchivePassphrase,
  createEncryptedArchiveService,
  createSqlCipherArchiveBoundary,
  parseArchiveManifestForValidation,
  type ArchiveDependencies,
  type ArchiveSnapshot,
} from '../exportArchive';

const SNAPSHOT: ArchiveSnapshot = {
  archiveFormatVersion: 1,
  schemaVersion: 1,
  counts: {
    profile: 1,
    conversations: 3,
    messages: 8,
    goals: 2,
    milestones: 1,
    actions: 4,
    action_transitions: 1,
    evidence: 2,
    memory_items: 3,
    memory_sources: 4,
    memory_confirmations: 1,
    coaching_requests: 3,
    audio_cleanup_queue: 0,
    usage_receipts: 3,
    migration_state: 0,
    mutation_receipts: 12,
  },
  contentHash: 'a'.repeat(64),
};

const EMPTY_SNAPSHOT: ArchiveSnapshot = {
  ...SNAPSHOT,
  counts: Object.fromEntries(
    Object.keys(SNAPSHOT.counts).map((table) => [table, 0]),
  ) as ArchiveSnapshot['counts'],
};

function makeHarness(overrides: Partial<ArchiveDependencies> = {}) {
  let activeSnapshot = SNAPSHOT;
  const files = {
    availableDiskSpace: jest.fn(async () => 100_000_000),
    size: jest.fn(async (uri: string) => uri.includes('selected') ? 2_000_000 : 1_000_000),
    createExportUri: jest.fn(() => 'file:///documents/taisa-backup.sqlite3'),
    stageSelectedArchive: jest.fn(async () => 'file:///sqlite/taisa-restore-input.db'),
    createCandidateUri: jest.fn(() => 'file:///sqlite/taisa-restore-candidate.db'),
    preparePromotion: jest.fn(async () => undefined),
    promoteCandidate: jest.fn(async () => undefined),
    rollbackPromotion: jest.fn(async () => { activeSnapshot = SNAPSHOT; }),
    commitPromotion: jest.fn(async () => undefined),
    cleanupTemporaryFiles: jest.fn(async () => undefined),
  };
  const sqlCipher = {
    exportPassphraseArchive: jest.fn(async () => SNAPSHOT),
    inspectPassphraseArchive: jest.fn(async () => SNAPSHOT),
    createDeviceEncryptedCandidate: jest.fn(async () => SNAPSHOT),
    checkpointActive: jest.fn(async () => undefined),
    fingerprintActive: jest.fn(async () => activeSnapshot),
  };
  const lifecycle = {
    invalidateClients: jest.fn(async () => undefined),
    close: jest.fn(async () => undefined),
    reopen: jest.fn(async () => undefined),
  };
  const dependencies: ArchiveDependencies = {
    files,
    sqlCipher,
    lifecycle,
    ...overrides,
  };
  return { service: createEncryptedArchiveService(dependencies), files, sqlCipher, lifecycle };
}

describe('encrypted archive recovery', () => {
  test('requires a separate matching passphrase of at least 12 characters before export', () => {
    expect(() => confirmArchivePassphrase('short', 'short')).toThrow('12');
    expect(() => confirmArchivePassphrase('            ', '            ')).toThrow('12');
    expect(() => confirmArchivePassphrase('a-long-passphrase', 'different-passphrase'))
      .toThrow('match');
    expect(confirmArchivePassphrase('a-long-passphrase', 'a-long-passphrase')).toEqual({
      value: 'a-long-passphrase',
      confirmed: true,
    });
  });

  test('exports an encrypted snapshot with entity counts and a content hash', async () => {
    const { service, sqlCipher } = makeHarness();
    const confirmed = confirmArchivePassphrase('correct horse battery', 'correct horse battery');

    await expect(service.exportEncryptedArchive(confirmed)).resolves.toEqual({
      uri: 'file:///documents/taisa-backup.sqlite3',
      snapshot: SNAPSHOT,
    });
    expect(sqlCipher.exportPassphraseArchive).toHaveBeenCalledWith({
      destinationUri: 'file:///documents/taisa-backup.sqlite3',
      passphrase: 'correct horse battery',
    });
  });

  test('restores only after the passphrase archive and device-encrypted candidate match', async () => {
    const { service, files, sqlCipher, lifecycle } = makeHarness();

    await expect(service.restoreEncryptedArchive(
      'file:///selected/backup.sqlite3',
      'correct horse battery',
    )).resolves.toEqual({ snapshot: SNAPSHOT });

    expect(sqlCipher.inspectPassphraseArchive.mock.invocationCallOrder[0]).toBeLessThan(
      sqlCipher.createDeviceEncryptedCandidate.mock.invocationCallOrder[0],
    );
    expect(files.preparePromotion.mock.invocationCallOrder[0]).toBeLessThan(
      files.promoteCandidate.mock.invocationCallOrder[0],
    );
    expect(lifecycle.close.mock.invocationCallOrder[0]).toBeLessThan(
      files.promoteCandidate.mock.invocationCallOrder[0],
    );
    expect(files.commitPromotion).toHaveBeenCalledTimes(1);
    expect(files.rollbackPromotion).not.toHaveBeenCalled();
    expect(files.cleanupTemporaryFiles).toHaveBeenCalledTimes(1);
  });

  test.each(['wrong passphrase', 'corrupted archive'])(
    'preserves the active database for a %s failure',
    async (message) => {
      const { service, sqlCipher, files, lifecycle } = makeHarness();
      sqlCipher.inspectPassphraseArchive.mockRejectedValueOnce(new Error(message));

      await expect(service.restoreEncryptedArchive(
        'file:///selected/backup.sqlite3',
        'incorrect but long',
      )).rejects.toMatchObject({ code: 'INVALID_ARCHIVE_OR_PASSPHRASE' });

      expect(lifecycle.close).not.toHaveBeenCalled();
      expect(files.preparePromotion).not.toHaveBeenCalled();
      expect(files.promoteCandidate).not.toHaveBeenCalled();
      expect(files.cleanupTemporaryFiles).toHaveBeenCalledTimes(1);
    },
  );

  test('rejects a newer archive schema before creating or promoting a candidate', async () => {
    const { service, sqlCipher, files } = makeHarness();
    sqlCipher.inspectPassphraseArchive.mockResolvedValueOnce({ ...SNAPSHOT, schemaVersion: 2 });

    await expect(service.restoreEncryptedArchive(
      'file:///selected/backup.sqlite3',
      'correct horse battery',
    )).rejects.toMatchObject({ code: 'UNSUPPORTED_ARCHIVE_VERSION' });
    expect(sqlCipher.createDeviceEncryptedCandidate).not.toHaveBeenCalled();
    expect(files.promoteCandidate).not.toHaveBeenCalled();
  });

  test('identifies a newer manifest before trying to interpret future entity tables', () => {
    const snapshot = parseArchiveManifestForValidation({
      archive_format_version: 1,
      schema_version: 2,
      counts_json: JSON.stringify({ ...SNAPSHOT.counts, future_private_entity: 7 }),
      content_hash: SNAPSHOT.contentHash,
    });

    expect(snapshot.schemaVersion).toBe(2);
    expect(snapshot.counts).toEqual(SNAPSHOT.counts);
  });

  test('fails before export when free space cannot hold a complete new archive', async () => {
    const { service, files, sqlCipher } = makeHarness();
    files.availableDiskSpace.mockResolvedValueOnce(1_100_000);

    await expect(service.exportEncryptedArchive(
      confirmArchivePassphrase('correct horse battery', 'correct horse battery'),
    )).rejects.toMatchObject({ code: 'INSUFFICIENT_FREE_SPACE' });
    expect(sqlCipher.exportPassphraseArchive).not.toHaveBeenCalled();
  });

  test('fails before staging restore when free space cannot hold input, candidate, and rollback', async () => {
    const { service, files, sqlCipher } = makeHarness();
    files.availableDiskSpace.mockResolvedValueOnce(3_000_000);

    await expect(service.restoreEncryptedArchive(
      'file:///selected/backup.sqlite3',
      'correct horse battery',
    )).rejects.toMatchObject({ code: 'INSUFFICIENT_FREE_SPACE' });
    expect(files.stageSelectedArchive).not.toHaveBeenCalled();
    expect(sqlCipher.inspectPassphraseArchive).not.toHaveBeenCalled();
  });

  test('rolls back and reopens the original database when promotion is interrupted', async () => {
    const { service, files, lifecycle } = makeHarness();
    files.promoteCandidate.mockRejectedValueOnce(new Error('interrupted move'));

    await expect(service.restoreEncryptedArchive(
      'file:///selected/backup.sqlite3',
      'correct horse battery',
    )).rejects.toMatchObject({ code: 'RESTORE_FAILED' });

    expect(files.rollbackPromotion).toHaveBeenCalledTimes(1);
    expect(lifecycle.reopen).toHaveBeenCalledTimes(1);
    expect(files.commitPromotion).not.toHaveBeenCalled();
    expect(files.cleanupTemporaryFiles).toHaveBeenCalledTimes(1);
  });

  test('rolls back when the promoted database count or hash does not match the candidate', async () => {
    const { service, sqlCipher, files, lifecycle } = makeHarness();
    sqlCipher.fingerprintActive.mockResolvedValueOnce({
      ...SNAPSHOT,
      contentHash: 'b'.repeat(64),
    });

    await expect(service.restoreEncryptedArchive(
      'file:///selected/backup.sqlite3',
      'correct horse battery',
    )).rejects.toMatchObject({ code: 'RESTORE_VERIFICATION_FAILED' });
    expect(files.rollbackPromotion).toHaveBeenCalledTimes(1);
    expect(lifecycle.reopen).toHaveBeenCalledTimes(2);
    expect(files.commitPromotion).not.toHaveBeenCalled();
  });

  test('normalizes candidate-open failures without leaking provider or database error content', async () => {
    const { service, sqlCipher } = makeHarness();
    sqlCipher.inspectPassphraseArchive.mockRejectedValueOnce(
      new Error('file is not a database: secret path and SQL text'),
    );

    let failure: unknown;
    try {
      await service.restoreEncryptedArchive(
        'file:///selected/backup.sqlite3',
        'correct horse battery',
      );
    } catch (error) {
      failure = error;
    }
    expect(failure).toBeInstanceOf(ArchiveOperationError);
    expect((failure as Error).message).toBe('The encrypted archive could not be opened.');
    expect((failure as Error).cause).toBeUndefined();
  });

  test('removes the backup-only manifest before the device candidate can become active', async () => {
    const execAsync = jest.fn(async () => undefined);
    const runAsync = jest.fn(async () => ({ changes: 0, lastInsertRowId: 0 }));
    const getFirstAsync = jest.fn(async (sql: string) => {
      if (sql === 'PRAGMA cipher_version') return { cipher_version: '4.6.1' };
      if (sql.includes('taisa_archive_manifest')) {
        return {
          archive_format_version: 1,
          schema_version: EMPTY_SNAPSHOT.schemaVersion,
          counts_json: JSON.stringify(EMPTY_SNAPSHOT.counts),
          content_hash: EMPTY_SNAPSHOT.contentHash,
        };
      }
      if (sql.includes('user_version')) return { user_version: EMPTY_SNAPSHOT.schemaVersion };
      if (sql.includes('LEFT JOIN')) return null;
      return { exported: 1 };
    });
    const getAllAsync = jest.fn(async (sql: string) => (
      sql.includes('integrity_check') ? [{ integrity_check: 'ok' }] : []
    ));
    const closeAsync = jest.fn(async () => undefined);
    const database = { execAsync, runAsync, getFirstAsync, getAllAsync, closeAsync };
    const readDeviceKey = jest.fn(async () => 'b'.repeat(64));
    const boundary = createSqlCipherArchiveBoundary({
      openActive: jest.fn(async () => database),
      openMaintenance: jest.fn(async () => database),
      deleteMaintenance: jest.fn(async () => undefined),
      readDeviceKey,
      sha256: jest.fn(async () => EMPTY_SNAPSHOT.contentHash),
    });

    await expect(boundary.createDeviceEncryptedCandidate({
      sourceUri: 'file:///restore-input.db',
      destinationUri: 'file:///device-candidate.db',
      passphrase: 'correct horse battery',
    })).resolves.toEqual(EMPTY_SNAPSHOT);

    expect(runAsync).toHaveBeenCalledWith(
      'ATTACH DATABASE ? AS source_archive KEY ?',
      ['file:///restore-input.db', 'correct horse battery'],
    );
    expect(readDeviceKey).toHaveBeenCalledTimes(1);
    expect(execAsync).toHaveBeenCalledWith(
      'DROP TABLE "device_candidate"."taisa_archive_manifest"',
    );
  });
});

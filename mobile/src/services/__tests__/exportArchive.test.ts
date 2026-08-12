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

const TRUSTED_SCHEMA_OBJECTS = Object.keys(SNAPSHOT.counts).map((name) => ({
  type: 'table', name, tbl_name: name, sql: `CREATE TABLE ${name} (id TEXT)`,
}));
const SOURCE_SCHEMA_OBJECTS = [
  ...TRUSTED_SCHEMA_OBJECTS,
  {
    type: 'table',
    name: 'taisa_archive_manifest',
    tbl_name: 'taisa_archive_manifest',
    sql: 'CREATE TABLE taisa_archive_manifest (id TEXT)',
  },
].sort((left, right) => left.type.localeCompare(right.type) || left.name.localeCompare(right.name));
const SORTED_TRUSTED_SCHEMA_OBJECTS = [...TRUSTED_SCHEMA_OBJECTS]
  .sort((left, right) => left.type.localeCompare(right.type) || left.name.localeCompare(right.name));

function makeHarness(overrides: Partial<ArchiveDependencies> = {}) {
  let activeSnapshot = SNAPSHOT;
  const files = {
    availableDiskSpace: jest.fn(async () => 100_000_000),
    size: jest.fn(async (uri: string) => uri.includes('selected') ? 2_000_000 : 1_000_000),
    createExportUri: jest.fn(() => 'file:///documents/taisa-backup.sqlite3'),
    discardExport: jest.fn(async () => undefined),
    stageSelectedArchive: jest.fn(async () => 'file:///sqlite/taisa-restore-input.db'),
    createCandidateUri: jest.fn(() => 'file:///sqlite/taisa-restore-candidate.db'),
    preparePromotion: jest.fn(async () => undefined),
    promoteCandidate: jest.fn(async () => undefined),
    rollbackPromotion: jest.fn(async () => { activeSnapshot = SNAPSHOT; }),
    commitPromotion: jest.fn(async () => undefined),
    cleanupTemporaryFiles: jest.fn(async () => undefined),
  };
  const sqlCipher = {
    assertExportable: jest.fn(async () => undefined),
    exportPassphraseArchive: jest.fn(async () => SNAPSHOT),
    inspectPassphraseArchive: jest.fn(async () => SNAPSHOT),
    createDeviceEncryptedCandidate: jest.fn(async () => SNAPSHOT),
    checkpointActive: jest.fn(async () => undefined),
    fingerprintActive: jest.fn(async () => activeSnapshot),
  };
  const lifecycle = {
    withMaintenance: async <T>(work: () => Promise<T>) => work(),
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

  test('does not report a committed restore as failed when post-commit artifact cleanup is interrupted', async () => {
    const { service, files } = makeHarness();
    files.cleanupTemporaryFiles.mockRejectedValueOnce(new Error('interrupted cleanup'));

    await expect(service.restoreEncryptedArchive(
      'file:///selected/backup.sqlite3',
      'correct horse battery',
    )).resolves.toEqual({ snapshot: SNAPSHOT });

    expect(files.commitPromotion).toHaveBeenCalledTimes(1);
    expect(files.rollbackPromotion).not.toHaveBeenCalled();
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

  test('keeps the export error content-safe if partial-artifact cleanup is interrupted', async () => {
    const { service, files, sqlCipher } = makeHarness();
    sqlCipher.exportPassphraseArchive.mockRejectedValueOnce(new Error('secret SQL and path'));
    files.discardExport.mockRejectedValueOnce(new Error('private cleanup path'));

    await expect(service.exportEncryptedArchive(
      confirmArchivePassphrase('correct horse battery', 'correct horse battery'),
    )).rejects.toMatchObject({ code: 'ARCHIVE_VERIFICATION_FAILED' });
  });

  test('creates no backup artifact while a nonterminal voice request references local audio', async () => {
    const { service, files, sqlCipher } = makeHarness();
    sqlCipher.assertExportable.mockRejectedValueOnce(
      new ArchiveOperationError('PENDING_VOICE_NOT_BACKED_UP'),
    );

    await expect(service.exportEncryptedArchive(
      confirmArchivePassphrase('correct horse battery', 'correct horse battery'),
    )).rejects.toMatchObject({ code: 'PENDING_VOICE_NOT_BACKED_UP' });

    expect(files.createExportUri).not.toHaveBeenCalled();
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

  test('never reopens an unverified active database when rollback itself fails', async () => {
    const { service, files, lifecycle } = makeHarness();
    files.promoteCandidate.mockRejectedValueOnce(new Error('private promotion detail'));
    files.rollbackPromotion.mockRejectedValueOnce(new Error('private rollback detail'));

    let failure: unknown;
    try {
      await service.restoreEncryptedArchive(
        'file:///selected/private-backup.sqlite3',
        'correct horse battery',
      );
    } catch (error) {
      failure = error;
    }

    expect(failure).toBeInstanceOf(ArchiveOperationError);
    expect(failure).toMatchObject({ code: 'RESTORE_FAILED' });
    expect((failure as Error).cause).toBeUndefined();
    expect(lifecycle.reopen).not.toHaveBeenCalled();
    expect(files.commitPromotion).not.toHaveBeenCalled();
  });

  test('normalizes reopen failure after rollback without exposing its cause', async () => {
    const { service, files, lifecycle } = makeHarness();
    files.promoteCandidate.mockRejectedValueOnce(new Error('private promotion detail'));
    lifecycle.reopen.mockRejectedValueOnce(new Error('private reopen detail'));

    let failure: unknown;
    try {
      await service.restoreEncryptedArchive(
        'file:///selected/private-backup.sqlite3',
        'correct horse battery',
      );
    } catch (error) {
      failure = error;
    }

    expect(files.rollbackPromotion).toHaveBeenCalledTimes(1);
    expect(failure).toBeInstanceOf(ArchiveOperationError);
    expect(failure).toMatchObject({ code: 'RESTORE_FAILED' });
    expect((failure as Error).cause).toBeUndefined();
    expect(files.commitPromotion).not.toHaveBeenCalled();
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

  test('sets the passphrase export user_version when sqlcipher_export starts it at zero', async () => {
    let passphraseExportVersion = 0;
    const execAsync = jest.fn(async (sql: string) => {
      if (sql === 'PRAGMA passphrase_export.user_version = 1') passphraseExportVersion = 1;
    });
    const database = {
      execAsync,
      runAsync: jest.fn(async () => ({ changes: 0, lastInsertRowId: 0 })),
      getFirstAsync: jest.fn(async (sql: string) => {
        if (sql.includes('passphrase_export.user_version')) {
          return { user_version: passphraseExportVersion };
        }
        if (sql.includes('main.user_version')) return { user_version: 1 };
        if (sql.includes('taisa_archive_manifest')) {
          return {
            archive_format_version: 1,
            schema_version: 1,
            counts_json: JSON.stringify(EMPTY_SNAPSHOT.counts),
            content_hash: EMPTY_SNAPSHOT.contentHash,
          };
        }
        if (sql.includes('LEFT JOIN')) return null;
        return { exported: 1 };
      }),
      getAllAsync: jest.fn(async (sql: string) => (
        sql.includes('integrity_check') ? [{ integrity_check: 'ok' }] : []
      )),
      closeAsync: jest.fn(async () => undefined),
    };
    const boundary = createSqlCipherArchiveBoundary({
      openActive: jest.fn(async () => database),
      openMaintenance: jest.fn(async () => database),
      openDeviceCandidate: jest.fn(async () => database),
      deleteMaintenance: jest.fn(async () => undefined),
      readDeviceKey: jest.fn(async () => 'b'.repeat(64)),
      sha256: jest.fn(async () => EMPTY_SNAPSHOT.contentHash),
    });

    await expect(boundary.exportPassphraseArchive({
      destinationUri: 'file:///backup.db',
      passphrase: 'correct horse battery',
    })).resolves.toEqual(EMPTY_SNAPSHOT);
    expect(execAsync).toHaveBeenCalledWith('PRAGMA passphrase_export.user_version = 1');
  });

  test('imports rows into a fresh trusted-schema candidate without cloning source schema', async () => {
    const source = {
      execAsync: jest.fn(async () => undefined),
      runAsync: jest.fn(async () => ({ changes: 0, lastInsertRowId: 0 })),
      getFirstAsync: jest.fn(async (sql: string) => {
        if (sql === 'PRAGMA cipher_version') return { cipher_version: '4.6.1' };
        if (sql.includes('source_archive.user_version')) return { user_version: 1 };
        if (sql.includes('taisa_archive_manifest')) {
          return {
            archive_format_version: 1,
            schema_version: 1,
            counts_json: JSON.stringify(EMPTY_SNAPSHOT.counts),
            content_hash: EMPTY_SNAPSHOT.contentHash,
          };
        }
        if (sql.includes('LEFT JOIN')) return null;
        return null;
      }),
      getAllAsync: jest.fn(async (sql: string) => {
        if (sql.includes('sqlite_schema')) return SOURCE_SCHEMA_OBJECTS;
        if (sql.includes('integrity_check')) return [{ integrity_check: 'ok' }];
        if (sql.includes('foreign_key_check')) return [];
        if (sql.includes('table_info')) {
          return [{ cid: 0, name: 'id', type: 'TEXT', notnull: 1, dflt_value: null, pk: 1 }];
        }
        return [];
      }),
      closeAsync: jest.fn(async () => undefined),
    };
    const candidate = {
      execAsync: jest.fn(async () => undefined),
      runAsync: jest.fn(async () => ({ changes: 1, lastInsertRowId: 0 })),
      getFirstAsync: jest.fn(async (sql: string) => {
        if (sql.includes('main.user_version')) return { user_version: 1 };
        if (sql.includes('LEFT JOIN')) return null;
        return null;
      }),
      getAllAsync: jest.fn(async (sql: string) => {
        if (sql.includes('sqlite_schema')) return SORTED_TRUSTED_SCHEMA_OBJECTS;
        if (sql.includes('integrity_check')) return [{ integrity_check: 'ok' }];
        if (sql.includes('foreign_key_check')) return [];
        if (sql.includes('table_info')) {
          return [{ cid: 0, name: 'id', type: 'TEXT', notnull: 1, dflt_value: null, pk: 1 }];
        }
        return [];
      }),
      closeAsync: jest.fn(async () => undefined),
    };
    const openDeviceCandidate = jest.fn(async () => candidate);
    const boundary = createSqlCipherArchiveBoundary({
      openActive: jest.fn(async () => candidate),
      openMaintenance: jest.fn(async () => source),
      openDeviceCandidate,
      deleteMaintenance: jest.fn(async () => undefined),
      readDeviceKey: jest.fn(async () => 'b'.repeat(64)),
      sha256: jest.fn(async () => EMPTY_SNAPSHOT.contentHash),
    });

    await expect(boundary.createDeviceEncryptedCandidate({
      sourceUri: 'file:///restore-input.db',
      destinationUri: 'file:///restore-candidate.db',
      passphrase: 'correct horse battery',
    })).resolves.toEqual(EMPTY_SNAPSHOT);

    expect(openDeviceCandidate).toHaveBeenCalledWith({
      destinationUri: 'file:///restore-candidate.db',
      deviceKey: 'b'.repeat(64),
    });
    expect(candidate.execAsync).toHaveBeenCalledWith('BEGIN IMMEDIATE');
    expect(candidate.execAsync).toHaveBeenCalledWith('PRAGMA defer_foreign_keys = ON');
    expect(candidate.getAllAsync).toHaveBeenCalledWith('PRAGMA foreign_key_check');
    expect(source.execAsync).toHaveBeenCalledWith('PRAGMA trusted_schema = OFF');
    expect(source.execAsync).toHaveBeenCalledWith('PRAGMA query_only = ON');
    expect(source.getFirstAsync).not.toHaveBeenCalledWith(
      expect.stringContaining("sqlcipher_export('device_candidate'"),
    );
  });

  test('rejects an archive with more than one authoritative local profile', async () => {
    const twoProfiles = {
      ...EMPTY_SNAPSHOT,
      counts: { ...EMPTY_SNAPSHOT.counts, profile: 2 },
    };
    const source = {
      execAsync: jest.fn(async () => undefined),
      runAsync: jest.fn(async () => ({ changes: 0, lastInsertRowId: 0 })),
      getFirstAsync: jest.fn(async (sql: string) => {
        if (sql === 'PRAGMA cipher_version') return { cipher_version: '4.6.1' };
        if (sql.includes('source_archive.user_version')) return { user_version: 1 };
        if (sql.includes('taisa_archive_manifest')) {
          return {
            archive_format_version: 1,
            schema_version: 1,
            counts_json: JSON.stringify(twoProfiles.counts),
            content_hash: twoProfiles.contentHash,
          };
        }
        if (sql.includes('LEFT JOIN')) return null;
        return null;
      }),
      getAllAsync: jest.fn(async (sql: string) => {
        if (sql.includes('sqlite_schema')) return SOURCE_SCHEMA_OBJECTS;
        if (sql.includes('integrity_check')) return [{ integrity_check: 'ok' }];
        if (sql.includes('foreign_key_check')) return [];
        if (sql.includes('"source_archive"."profile"')) return [{ id: 'one' }, { id: 'two' }];
        return [];
      }),
      closeAsync: jest.fn(async () => undefined),
    };
    const boundary = createSqlCipherArchiveBoundary({
      openActive: jest.fn(async () => source),
      openMaintenance: jest.fn(async () => source),
      openDeviceCandidate: jest.fn(async () => source),
      deleteMaintenance: jest.fn(async () => undefined),
      readDeviceKey: jest.fn(async () => 'b'.repeat(64)),
      sha256: jest.fn(async () => EMPTY_SNAPSHOT.contentHash),
    });

    await expect(boundary.inspectPassphraseArchive({
      sourceUri: 'file:///restore-input.db',
      passphrase: 'correct horse battery',
    })).rejects.toThrow('profile');
  });

  test.each(['foreign-key', 'corrupt-search-index'] as const)(
    'rejects a source archive with a %s integrity failure',
    async (failure) => {
      const source = {
        execAsync: jest.fn(async () => undefined),
        getFirstAsync: jest.fn(async (sql: string) => {
          if (sql === 'PRAGMA cipher_version') return { cipher_version: '4.6.1' };
          if (sql.includes('source_archive.user_version')) return { user_version: 1 };
          if (sql.includes('taisa_archive_manifest')) {
            return {
              archive_format_version: 1,
              schema_version: 1,
              counts_json: JSON.stringify(EMPTY_SNAPSHOT.counts),
              content_hash: EMPTY_SNAPSHOT.contentHash,
            };
          }
          if (sql.includes('LEFT JOIN')) return null;
          return null;
        }),
        getAllAsync: jest.fn(async (sql: string) => {
          if (sql.includes('sqlite_schema')) return SOURCE_SCHEMA_OBJECTS;
          if (sql.includes('integrity_check')) return [{ integrity_check: 'ok' }];
          if (sql.includes('foreign_key_check')) {
            return failure === 'foreign-key' ? [{ table: 'messages', rowid: 1 }] : [];
          }
          return [];
        }),
        runAsync: jest.fn(async (sql: string) => {
          if (failure === 'corrupt-search-index' && sql.includes('integrity-check')) {
            throw new Error('database disk image is malformed');
          }
          return { changes: 0, lastInsertRowId: 0 };
        }),
        closeAsync: jest.fn(async () => undefined),
      };
      const boundary = createSqlCipherArchiveBoundary({
        openActive: jest.fn(async () => source),
        openMaintenance: jest.fn(async () => source),
        openDeviceCandidate: jest.fn(async () => source),
        deleteMaintenance: jest.fn(async () => undefined),
        readDeviceKey: jest.fn(async () => 'b'.repeat(64)),
        sha256: jest.fn(async () => EMPTY_SNAPSHOT.contentHash),
      });

      await expect(boundary.inspectPassphraseArchive({
        sourceUri: 'file:///restore-input.db',
        passphrase: 'correct horse battery',
      })).rejects.toThrow(failure === 'foreign-key' ? 'foreign key' : 'search index');
    },
  );

  test('rejects extra or omitted source columns instead of importing archive-owned schema', async () => {
    const source = {
      execAsync: jest.fn(async () => undefined),
      runAsync: jest.fn(async () => ({ changes: 0, lastInsertRowId: 0 })),
      getFirstAsync: jest.fn(async (sql: string) => {
        if (sql === 'PRAGMA cipher_version') return { cipher_version: '4.6.1' };
        if (sql.includes('source_archive.user_version')) return { user_version: 1 };
        if (sql.includes('taisa_archive_manifest')) {
          return {
            archive_format_version: 1,
            schema_version: 1,
            counts_json: JSON.stringify(EMPTY_SNAPSHOT.counts),
            content_hash: EMPTY_SNAPSHOT.contentHash,
          };
        }
        if (sql.includes('LEFT JOIN')) return null;
        return null;
      }),
      getAllAsync: jest.fn(async (sql: string) => {
        if (sql.includes('sqlite_schema')) return SOURCE_SCHEMA_OBJECTS;
        if (sql.includes('integrity_check')) return [{ integrity_check: 'ok' }];
        if (sql.includes('foreign_key_check')) return [];
        if (sql.includes('table_info')) {
          return [
            { cid: 0, name: 'id', type: 'TEXT', notnull: 1, dflt_value: null, pk: 1 },
            { cid: 1, name: 'archive_owned_extra', type: 'TEXT', notnull: 0, dflt_value: null, pk: 0 },
          ];
        }
        return [];
      }),
      closeAsync: jest.fn(async () => undefined),
    };
    const candidate = {
      execAsync: jest.fn(async () => undefined),
      runAsync: jest.fn(async () => ({ changes: 0, lastInsertRowId: 0 })),
      getFirstAsync: jest.fn(async () => null),
      getAllAsync: jest.fn(async (sql: string) => (
        sql.includes('sqlite_schema')
          ? SORTED_TRUSTED_SCHEMA_OBJECTS
          : sql.includes('table_info')
          ? [{ cid: 0, name: 'id', type: 'TEXT', notnull: 1, dflt_value: null, pk: 1 }]
          : []
      )),
      closeAsync: jest.fn(async () => undefined),
    };
    const boundary = createSqlCipherArchiveBoundary({
      openActive: jest.fn(async () => candidate),
      openMaintenance: jest.fn(async () => source),
      openDeviceCandidate: jest.fn(async () => candidate),
      deleteMaintenance: jest.fn(async () => undefined),
      readDeviceKey: jest.fn(async () => 'b'.repeat(64)),
      sha256: jest.fn(async () => EMPTY_SNAPSHOT.contentHash),
    });

    await expect(boundary.createDeviceEncryptedCandidate({
      sourceUri: 'file:///restore-input.db',
      destinationUri: 'file:///restore-candidate.db',
      passphrase: 'correct horse battery',
    })).rejects.toThrow('trusted schema');
    expect(candidate.runAsync).not.toHaveBeenCalled();
  });
});

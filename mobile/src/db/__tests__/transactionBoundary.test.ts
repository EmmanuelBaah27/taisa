import { withRepositoryTransaction } from '../types';

describe('encrypted repository transaction boundary', () => {
  test('uses and serializes the already-keyed connection instead of Expo exclusive new connections', async () => {
    const events: string[] = [];
    let releaseFirst!: () => void;
    const firstCanFinish = new Promise<void>((resolve) => { releaseFirst = resolve; });
    const database = {
      execAsync: jest.fn(async () => {}),
      getFirstAsync: jest.fn(async () => null),
      getAllAsync: jest.fn(async () => []),
      runAsync: jest.fn(async () => ({ lastInsertRowId: 0, changes: 0 })),
      withTransactionAsync: jest.fn(async (work: () => Promise<void>) => {
        await work();
      }),
      withExclusiveTransactionAsync: jest.fn(async () => {
        throw new Error('must not open an unkeyed SQLCipher connection');
      }),
    };

    const first = withRepositoryTransaction(database as never, async (transaction) => {
      expect(transaction).toBe(database);
      events.push('first-start');
      await firstCanFinish;
      events.push('first-end');
    });
    const second = withRepositoryTransaction(database as never, async () => {
      events.push('second');
    });
    await Promise.resolve();
    expect(events).toEqual(['first-start']);
    releaseFirst();
    await Promise.all([first, second]);

    expect(events).toEqual(['first-start', 'first-end', 'second']);
    expect(database.withTransactionAsync).toHaveBeenCalledTimes(2);
    expect(database.withExclusiveTransactionAsync).not.toHaveBeenCalled();
  });
});

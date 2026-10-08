import { replaceReadableStoreAuthority } from '../restoredStoreAuthority';

describe('restored local authority', () => {
  test('clears every readable store before rehydrating the restored profile and conversations', async () => {
    const states: string[] = [];
    let release!: () => void;
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const operation = replaceReadableStoreAuthority({
      clearCareer: () => { states.push('clear-career'); },
      clearThreads: () => { states.push('clear-threads'); },
      clearChat: () => { states.push('clear-chat'); },
      clearJournal: () => { states.push('clear-journal'); },
      invalidateCapture: () => { states.push('invalidate-capture'); },
      fetchProfile: async () => { states.push('fetch-profile'); await gate; },
      fetchThreads: async () => { states.push('fetch-threads'); await gate; },
    });

    expect(states.slice(0, 5)).toEqual([
      'clear-career',
      'clear-threads',
      'clear-chat',
      'clear-journal',
      'invalidate-capture',
    ]);
    expect(states).toEqual(expect.arrayContaining(['fetch-profile', 'fetch-threads']));
    release();
    await operation;
  });

  test('keeps readable stores cleared when restored authority cannot be hydrated', async () => {
    let cleared = false;
    await expect(replaceReadableStoreAuthority({
      clearCareer: () => { cleared = true; },
      clearThreads: jest.fn(),
      clearChat: jest.fn(),
      clearJournal: jest.fn(),
      invalidateCapture: jest.fn(),
      fetchProfile: async () => { throw new Error('restored archive unavailable'); },
      fetchThreads: jest.fn(async () => undefined),
    })).rejects.toThrow('restored archive unavailable');
    expect(cleared).toBe(true);
  });
});

import { createInstallationIdentity } from '../installationIdentity';

describe('device installation identity', () => {
  test('creates one stable rate-limit identifier without reading or writing profile identity', async () => {
    const values = new Map<string, string>();
    const reads: string[] = [];
    const writes: string[] = [];
    const identity = createInstallationIdentity({
      async getItem(key) {
        reads.push(key);
        return values.get(key) ?? null;
      },
      async setItem(key, value) {
        writes.push(key);
        values.set(key, value);
      },
      createId: () => 'installation-123',
    });

    const [first, concurrent] = await Promise.all([identity.get(), identity.get()]);
    const later = await identity.get();

    expect(first).toBe('installation-123');
    expect(concurrent).toBe(first);
    expect(later).toBe(first);
    expect(writes).toEqual(['taisa.installation-id.v1']);
    expect(reads).not.toContain('userId');
    expect(writes).not.toContain('userId');
  });

  test('releases a failed load without creating a rejected cleanup promise', async () => {
    let first = true;
    const identity = createInstallationIdentity({
      async getItem() {
        if (first) {
          first = false;
          throw new Error('secure store unavailable');
        }
        return null;
      },
      async setItem() {},
      createId: () => 'installation-after-retry',
    });

    await expect(identity.get()).rejects.toThrow('secure store unavailable');
    await expect(identity.get()).resolves.toBe('installation-after-retry');
  });
});

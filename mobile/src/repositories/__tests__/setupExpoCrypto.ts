jest.mock('expo-crypto', () => {
  const actual = jest.requireActual<typeof import('expo-crypto')>('expo-crypto');
  const { createHash, randomBytes } = jest.requireActual<typeof import('node:crypto')>('node:crypto');

  return {
    ...actual,
    digestStringAsync: async (_algorithm: string, value: string): Promise<string> =>
      createHash('sha256').update(value, 'utf8').digest('hex'),
    getRandomBytes: (byteCount: number): Uint8Array => new Uint8Array(randomBytes(byteCount)),
    getRandomBytesAsync: async (byteCount: number): Promise<Uint8Array> =>
      new Uint8Array(randomBytes(byteCount)),
  };
});

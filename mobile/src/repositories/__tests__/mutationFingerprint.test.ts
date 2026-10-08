import * as Crypto from 'expo-crypto';

describe('mutation fingerprint test boundary', () => {
  test('preserves the Expo Crypto module surface outside digesting', async () => {
    await expect(Crypto.getRandomBytesAsync(8)).resolves.toHaveLength(8);
  });
});

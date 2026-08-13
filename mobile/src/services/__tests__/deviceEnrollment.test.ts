jest.mock('expo-secure-store', () => ({
  getItemAsync: jest.fn(),
  setItemAsync: jest.fn(),
  deleteItemAsync: jest.fn(),
  WHEN_UNLOCKED_THIS_DEVICE_ONLY: 'WHEN_UNLOCKED_THIS_DEVICE_ONLY',
}));

import * as SecureStore from 'expo-secure-store';
import {
  clearDeviceCredential,
  createDeviceEnrollmentClient,
  getDeviceCredential,
} from '../deviceEnrollment';

describe('device enrollment', () => {
  beforeEach(() => jest.clearAllMocks());

  test('enrolls once and stores only the issued bearer token in device-only secure storage', async () => {
    const token = 'issued-device-token-that-is-long-enough-for-storage';
    const post = jest.fn().mockResolvedValue({
      data: { success: true, data: { credentialId: 'credential-1', token } },
    });

    await expect(createDeviceEnrollmentClient({ post }).enroll('one-time-code'))
      .resolves.toEqual({ credentialId: 'credential-1' });
    expect(post).toHaveBeenCalledWith('/device-enrollments', { code: 'one-time-code' });
    expect(SecureStore.setItemAsync).toHaveBeenCalledWith(
      'taisa.device-credential.v1',
      token,
      { keychainAccessible: 'WHEN_UNLOCKED_THIS_DEVICE_ONLY' },
    );
  });

  test('returns a stored token and supports local revocation', async () => {
    const token = 'stored-device-token-that-is-long-enough-to-use';
    (SecureStore.getItemAsync as jest.Mock).mockResolvedValue(token);
    await expect(getDeviceCredential()).resolves.toBe(token);
    await clearDeviceCredential();
    expect(SecureStore.deleteItemAsync).toHaveBeenCalledWith('taisa.device-credential.v1');
  });

  test('rejects malformed enrollment responses without persisting them', async () => {
    const post = jest.fn().mockResolvedValue({ data: { success: true, data: { token: '' } } });
    await expect(createDeviceEnrollmentClient({ post }).enroll('code'))
      .rejects.toThrow('Device enrollment failed');
    expect(SecureStore.setItemAsync).not.toHaveBeenCalled();
  });
});

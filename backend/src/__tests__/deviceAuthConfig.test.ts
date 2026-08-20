import { readDeviceAuthConfig, readFeedbackConfig } from '../config/deviceAuth';

const valid = {
  TAISA_DEVICE_AUTH_REQUIRED: 'true',
  TAISA_DEVICE_CREDENTIAL_PEPPER: 'a-production-pepper-that-is-long-enough',
  TAISA_DEVICE_AUTH_DATABASE_PATH: '/tmp/taisa-device-auth.sqlite',
  TAISA_DEVICE_ENROLLMENT_CODE: 'one-time-code',
  TAISA_DEVICE_ENROLLMENT_EXPIRES_AT: '2099-01-01T00:00:00.000Z',
};

test('disabled device authentication requires no secrets', () => {
  expect(readDeviceAuthConfig({})).toEqual({ required: false });
});

test('enabled device authentication requires complete fail-closed configuration', () => {
  expect(readDeviceAuthConfig(valid)).toEqual({
    required: true,
    pepper: valid.TAISA_DEVICE_CREDENTIAL_PEPPER,
    databasePath: valid.TAISA_DEVICE_AUTH_DATABASE_PATH,
    enrollmentCode: valid.TAISA_DEVICE_ENROLLMENT_CODE,
    enrollmentExpiresAt: valid.TAISA_DEVICE_ENROLLMENT_EXPIRES_AT,
  });
  expect(() => readDeviceAuthConfig({ ...valid, TAISA_DEVICE_CREDENTIAL_PEPPER: '' }))
    .toThrow('Device authentication configuration is incomplete');
  expect(() => readDeviceAuthConfig({ ...valid, TAISA_DEVICE_ENROLLMENT_EXPIRES_AT: 'never' }))
    .toThrow('Device authentication configuration is incomplete');
});

test('production refuses to start without device authentication', () => {
  expect(() => readDeviceAuthConfig({ NODE_ENV: 'production' }))
    .toThrow('Device authentication is required in production');
});

test('feedback storage is optional locally but rejects partial configuration', () => {
  expect(readFeedbackConfig({})).toBeNull();
  expect(readFeedbackConfig({
    TAISA_FEEDBACK_ENCRYPTION_KEY: Buffer.alloc(32, 4).toString('base64'),
    TAISA_FEEDBACK_DATABASE_PATH: '/tmp/taisa-feedback.sqlite',
  })).toEqual({
    encryptionKeyBase64: Buffer.alloc(32, 4).toString('base64'),
    databasePath: '/tmp/taisa-feedback.sqlite',
  });
  expect(() => readFeedbackConfig({ TAISA_FEEDBACK_DATABASE_PATH: '/tmp/only.sqlite' }))
    .toThrow('Feedback storage configuration is incomplete');
});

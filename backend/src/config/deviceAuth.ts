export type DeviceAuthConfig =
  | { required: false }
  | {
      required: true;
      pepper: string;
      databasePath: string;
      enrollmentCode: string;
      enrollmentExpiresAt: string;
    };

type Environment = Record<string, string | undefined>;

export function readDeviceAuthConfig(environment: Environment = process.env): DeviceAuthConfig {
  const required = environment.TAISA_DEVICE_AUTH_REQUIRED === 'true';
  if (!required) {
    if (environment.NODE_ENV === 'production') {
      throw new Error('Device authentication is required in production');
    }
    return { required: false };
  }

  const pepper = environment.TAISA_DEVICE_CREDENTIAL_PEPPER ?? '';
  const databasePath = environment.TAISA_DEVICE_AUTH_DATABASE_PATH ?? '';
  const enrollmentCode = environment.TAISA_DEVICE_ENROLLMENT_CODE ?? '';
  const enrollmentExpiresAt = environment.TAISA_DEVICE_ENROLLMENT_EXPIRES_AT ?? '';
  if (
    pepper.length < 24
    || databasePath.trim().length === 0
    || enrollmentCode.trim().length === 0
    || !Number.isFinite(Date.parse(enrollmentExpiresAt))
  ) {
    throw new Error('Device authentication configuration is incomplete');
  }
  return { required: true, pepper, databasePath, enrollmentCode, enrollmentExpiresAt };
}

export interface FeedbackConfig {
  readonly encryptionKeyBase64: string;
  readonly databasePath: string;
}

export function readFeedbackConfig(environment: Environment = process.env): FeedbackConfig | null {
  const encryptionKeyBase64 = environment.TAISA_FEEDBACK_ENCRYPTION_KEY ?? '';
  const databasePath = environment.TAISA_FEEDBACK_DATABASE_PATH ?? '';
  if (!encryptionKeyBase64 && !databasePath) return null;
  if (!encryptionKeyBase64 || !databasePath) {
    throw new Error('Feedback storage configuration is incomplete');
  }
  return { encryptionKeyBase64, databasePath };
}

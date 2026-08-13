import path from 'path';

type Environment = Record<string, string | undefined>;

export interface ProductionConfig {
  readonly publicOrigin: string;
}

function positiveNumber(environment: Environment, name: string): boolean {
  const value = Number(environment[name]);
  return Number.isFinite(value) && value > 0;
}

function isWithinVolume(filePath: string | undefined, volumePath: string): boolean {
  if (!filePath || !path.isAbsolute(filePath)) return false;
  const relative = path.relative(volumePath, filePath);
  return relative !== '' && !relative.startsWith('..') && !path.isAbsolute(relative);
}

export function readProductionConfig(environment: Environment = process.env): ProductionConfig | null {
  if (environment.NODE_ENV !== 'production') return null;
  const publicOrigin = environment.TAISA_PUBLIC_ORIGIN ?? '';
  const volumePath = environment.RAILWAY_VOLUME_MOUNT_PATH ?? '';
  let validOrigin = false;
  try {
    const parsed = new URL(publicOrigin);
    validOrigin = parsed.protocol === 'https:' && parsed.origin === publicOrigin;
  } catch {
    validOrigin = false;
  }

  const databasePaths = [
    environment.DB_PATH,
    environment.TAISA_USAGE_LEDGER_PATH,
    environment.TAISA_DEVICE_AUTH_DATABASE_PATH,
    environment.TAISA_FEEDBACK_DATABASE_PATH,
  ];
  const uniqueDatabasePaths = new Set(databasePaths);
  const feedbackKey = Buffer.from(environment.TAISA_FEEDBACK_ENCRYPTION_KEY ?? '', 'base64');
  const valid = validOrigin
    && path.isAbsolute(volumePath)
    && databasePaths.every((item) => isWithinVolume(item, volumePath))
    && uniqueDatabasePaths.size === databasePaths.length
    && feedbackKey.length === 32
    && Boolean(environment.OPENAI_API_KEY?.trim())
    && positiveNumber(environment, 'TAISA_AI_COST_CEILING_PER_REQUEST_USD')
    && positiveNumber(environment, 'TAISA_AI_COST_CEILING_DAILY_USD')
    && positiveNumber(environment, 'TAISA_AI_COST_CEILING_MONTHLY_USD')
    && positiveNumber(environment, 'TAISA_TRANSCRIPTION_MAX_DURATION_SECONDS')
    && positiveNumber(environment, 'TAISA_TRANSCRIPTION_MAX_UPLOAD_BYTES')
    && positiveNumber(environment, 'TAISA_TRANSCRIPTION_PRICE_USD_PER_MINUTE');
  if (!valid) throw new Error('Production configuration is incomplete');
  return { publicOrigin };
}

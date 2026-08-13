import { readProductionConfig } from '../config/production';

const volume = '/data';
const valid = {
  NODE_ENV: 'production',
  TAISA_PUBLIC_ORIGIN: 'https://taisa.example',
  RAILWAY_VOLUME_MOUNT_PATH: volume,
  DB_PATH: `${volume}/legacy.sqlite`,
  TAISA_USAGE_LEDGER_PATH: `${volume}/usage.sqlite`,
  TAISA_DEVICE_AUTH_DATABASE_PATH: `${volume}/device-auth.sqlite`,
  TAISA_FEEDBACK_DATABASE_PATH: `${volume}/feedback.sqlite`,
  TAISA_FEEDBACK_ENCRYPTION_KEY: Buffer.alloc(32, 8).toString('base64'),
  TAISA_AI_COST_CEILING_PER_REQUEST_USD: '0.25',
  TAISA_AI_COST_CEILING_DAILY_USD: '2',
  TAISA_AI_COST_CEILING_MONTHLY_USD: '20',
  TAISA_TRANSCRIPTION_MAX_DURATION_SECONDS: '300',
  TAISA_TRANSCRIPTION_MAX_UPLOAD_BYTES: '26214400',
  TAISA_TRANSCRIPTION_PRICE_USD_PER_MINUTE: '0.006',
  OPENAI_API_KEY: 'configured-secret',
};

test('production accepts one HTTPS origin and places every mutable database on the volume', () => {
  expect(readProductionConfig(valid)).toEqual({ publicOrigin: 'https://taisa.example' });
});

test.each([
  ['TAISA_PUBLIC_ORIGIN', 'http://taisa.example'],
  ['RAILWAY_VOLUME_MOUNT_PATH', ''],
  ['TAISA_USAGE_LEDGER_PATH', '/tmp/usage.sqlite'],
  ['TAISA_FEEDBACK_DATABASE_PATH', `${volume}/usage.sqlite`],
  ['TAISA_FEEDBACK_DATABASE_PATH', '/tmp/feedback.sqlite'],
  ['TAISA_AI_COST_CEILING_DAILY_USD', ''],
  ['OPENAI_API_KEY', ''],
])('production fails closed for invalid %s', (name, value) => {
  expect(() => readProductionConfig({ ...valid, [name]: value })).toThrow('Production configuration is incomplete');
});

test('non-production does not require hosted configuration', () => {
  expect(readProductionConfig({ NODE_ENV: 'test' })).toBeNull();
});

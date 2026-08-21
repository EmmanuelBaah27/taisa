import { readFileSync, writeFileSync } from 'fs';
import { COACHING_EVALUATION_THRESHOLDS, type ProviderEvaluationDecision } from './run';
import { COACHING_EVALUATION_PACK_VERSION } from './scenarios';

export type { ProviderEvaluationDecision } from './run';

export interface ParityCliIo {
  readFile: (path: string) => string;
  writeFile: (path: string, output: string, options: { flag: 'wx' }) => void;
  writeStderr: (output: string) => void;
}

const defaultParityCliIo: ParityCliIo = {
  readFile: (target) => readFileSync(target, 'utf8'),
  writeFile: (target, output, options) => writeFileSync(target, output, options),
  writeStderr: (output) => process.stderr.write(output),
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function thresholdsMatch(value: unknown): boolean {
  if (!isRecord(value)) return false;
  const expectedEntries = Object.entries(COACHING_EVALUATION_THRESHOLDS);
  return Object.keys(value).length === expectedEntries.length &&
    expectedEntries.every(([key, threshold]) => value[key] === threshold);
}

const providerDecisionKeys = [
  'provider', 'packVersion', 'automatedPassed', 'manualPassed', 'passed',
] as const;

function hasExactKeys(value: Record<string, unknown>, expectedKeys: readonly string[]): boolean {
  const actualKeys = Object.keys(value).sort();
  const sortedExpectedKeys = [...expectedKeys].sort();
  return actualKeys.length === sortedExpectedKeys.length &&
    actualKeys.every((key, index) => key === sortedExpectedKeys[index]);
}

function normalizeProviderDecision(
  value: unknown,
  expectedProvider?: ProviderEvaluationDecision['provider'],
): ProviderEvaluationDecision {
  if (!isRecord(value) || !hasExactKeys(value, providerDecisionKeys) ||
      (value.provider !== 'openai' && value.provider !== 'anthropic') ||
      (expectedProvider !== undefined && value.provider !== expectedProvider) ||
      typeof value.packVersion !== 'string' || value.packVersion.length === 0 ||
      typeof value.automatedPassed !== 'boolean' || typeof value.manualPassed !== 'boolean' ||
      typeof value.passed !== 'boolean' ||
      value.passed !== (value.automatedPassed && value.manualPassed)) {
    throw new Error('Provider evaluation decision is invalid');
  }
  return {
    provider: value.provider,
    packVersion: value.packVersion,
    automatedPassed: value.automatedPassed,
    manualPassed: value.manualPassed,
    passed: value.passed,
  };
}

function parseProviderDecision(value: unknown): ProviderEvaluationDecision {
  if (!isRecord(value) ||
      !hasExactKeys(value, [...providerDecisionKeys, 'thresholds']) ||
      !thresholdsMatch(value.thresholds)) {
    throw new Error('Provider evaluation decision is invalid');
  }
  return normalizeProviderDecision({
    provider: value.provider,
    packVersion: value.packVersion,
    automatedPassed: value.automatedPassed,
    manualPassed: value.manualPassed,
    passed: value.passed,
  });
}

export function buildProviderParityDecision(
  openai: ProviderEvaluationDecision,
  anthropic: ProviderEvaluationDecision,
): { packVersion: string; passed: boolean; providers: readonly ProviderEvaluationDecision[] } {
  const normalizedOpenAI = normalizeProviderDecision(openai, 'openai');
  const normalizedAnthropic = normalizeProviderDecision(anthropic, 'anthropic');
  if (normalizedOpenAI.packVersion !== normalizedAnthropic.packVersion) {
    throw new Error('Provider evaluation pack versions must match');
  }
  if (normalizedOpenAI.packVersion !== COACHING_EVALUATION_PACK_VERSION ||
      normalizedAnthropic.packVersion !== COACHING_EVALUATION_PACK_VERSION) {
    throw new Error('Provider evaluation pack version must match the current coaching evaluation pack');
  }
  return {
    packVersion: normalizedOpenAI.packVersion,
    passed: normalizedOpenAI.passed && normalizedAnthropic.passed,
    providers: [normalizedOpenAI, normalizedAnthropic],
  };
}

function parseExactFlags(argv: string[], names: readonly string[]): Record<string, string> {
  if (argv.length !== names.length) throw new Error('Invalid parity arguments');
  const allowed = new Set(names);
  const values: Record<string, string> = {};
  for (const argument of argv) {
    const separator = argument.indexOf('=');
    if (!argument.startsWith('--') || separator < 3) throw new Error('Invalid parity argument');
    const name = argument.slice(2, separator);
    const value = argument.slice(separator + 1);
    if (!allowed.has(name) || name in values || value.length === 0) {
      throw new Error('Invalid parity argument');
    }
    values[name] = value;
  }
  if (names.some((name) => !(name in values))) throw new Error('Missing parity argument');
  return values;
}

export function runParityCli(argv: string[], io: ParityCliIo = defaultParityCliIo): 0 | 1 {
  try {
    const flags = parseExactFlags(argv, ['openai-decision', 'anthropic-decision', 'parity-output']);
    const openai = parseProviderDecision(JSON.parse(io.readFile(flags['openai-decision'])));
    const anthropic = parseProviderDecision(JSON.parse(io.readFile(flags['anthropic-decision'])));
    const decision = buildProviderParityDecision(openai, anthropic);
    io.writeFile(flags['parity-output'], `${JSON.stringify({
      packVersion: decision.packVersion,
      thresholds: COACHING_EVALUATION_THRESHOLDS,
      passed: decision.passed,
      providers: decision.providers,
    }, null, 2)}\n`, { flag: 'wx' });
    if (!decision.passed) {
      io.writeStderr('EVAL_COACHING_PARITY_FAILED\n');
      return 1;
    }
    return 0;
  } catch {
    io.writeStderr('EVAL_COACHING_PARITY_FAILED\n');
    return 1;
  }
}

if (require.main === module) {
  process.exitCode = runParityCli(process.argv.slice(2));
}

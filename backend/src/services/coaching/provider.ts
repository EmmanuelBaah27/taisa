import type { UsageReceipt } from '@taisa/shared';

export interface ProviderCoachingInput {
  systemPrompt: string;
  userPrompt: string;
}

export interface ProviderCoachingResult {
  payload: unknown;
  usage: UsageReceipt;
}

export interface CoachingProvider {
  readonly id: 'openai' | 'anthropic';
  estimateMaximumUsage?(input: ProviderCoachingInput): UsageReceipt;
  respond(input: ProviderCoachingInput): Promise<ProviderCoachingResult>;
}

export interface CoachingProviderConfig {
  model: string;
  inputPriceUsdPerMillionTokens: number;
  outputPriceUsdPerMillionTokens: number;
  maxOutputTokens: number;
  structuredOutputInputTokenOverhead: number;
}

export type CoachingProviderId = 'openai' | 'anthropic';
export type CoachingEnvironment = Record<string, string | undefined>;
export type ProviderRegistry = Record<CoachingProviderId, CoachingProvider>;

function requireValue(environment: CoachingEnvironment, name: string): string {
  const value = environment[name]?.trim();
  if (!value) throw new Error(`${name} must be configured`);
  return value;
}

function requireNonNegativeNumber(environment: CoachingEnvironment, name: string): number {
  const raw = requireValue(environment, name);
  const value = Number(raw);
  if (!Number.isFinite(value) || value < 0) {
    throw new Error(`${name} must be a non-negative number`);
  }
  return value;
}

function requirePositiveInteger(environment: CoachingEnvironment, name: string): number {
  const value = requireNonNegativeNumber(environment, name);
  if (!Number.isSafeInteger(value) || value === 0) {
    throw new Error(`${name} must be a positive integer`);
  }
  return value;
}

export function readProviderConfig(
  environment: CoachingEnvironment,
  provider: CoachingProviderId,
): CoachingProviderConfig {
  const prefix = provider === 'openai' ? 'TAISA_OPENAI' : 'TAISA_ANTHROPIC';
  return {
    model: requireValue(environment, `${prefix}_MODEL`),
    inputPriceUsdPerMillionTokens: requireNonNegativeNumber(
      environment,
      `${prefix}_INPUT_PRICE_USD_PER_MILLION_TOKENS`,
    ),
    outputPriceUsdPerMillionTokens: requireNonNegativeNumber(
      environment,
      `${prefix}_OUTPUT_PRICE_USD_PER_MILLION_TOKENS`,
    ),
    maxOutputTokens: requirePositiveInteger(environment, `${prefix}_MAX_OUTPUT_TOKENS`),
    structuredOutputInputTokenOverhead: requirePositiveInteger(
      environment,
      `${prefix}_STRUCTURED_OUTPUT_INPUT_TOKEN_OVERHEAD`,
    ),
  };
}

function requireProviderId(value: string | undefined): CoachingProviderId {
  const configured = value?.trim();
  if (configured !== 'openai' && configured !== 'anthropic') {
    throw new Error('TAISA_COACHING_PROVIDER must be configured as openai or anthropic');
  }
  return configured;
}

export function getConfiguredProviderPairSettings(
  environment: CoachingEnvironment = process.env,
) {
  const primaryId = requireProviderId(environment.TAISA_COACHING_PROVIDER);
  const fallbackId: CoachingProviderId = primaryId === 'openai' ? 'anthropic' : 'openai';
  return {
    primaryId,
    fallbackId,
    configs: {
      openai: readProviderConfig(environment, 'openai'),
      anthropic: readProviderConfig(environment, 'anthropic'),
    },
  };
}

export function getConfiguredProviderSettings(
  environment: CoachingEnvironment = process.env,
): { providerId: CoachingProviderId; config: CoachingProviderConfig } {
  const providerId = requireProviderId(environment.TAISA_COACHING_PROVIDER);
  return { providerId, config: readProviderConfig(environment, providerId) };
}

export function getConfiguredProvider(
  environment: CoachingEnvironment = process.env,
  providers?: ProviderRegistry,
): CoachingProvider {
  const { providerId } = getConfiguredProviderSettings(environment);
  return createProviderForId(providerId, environment, providers);
}

export function createProviderForId(
  provider: CoachingProviderId,
  environment: CoachingEnvironment = process.env,
  providers?: ProviderRegistry,
): CoachingProvider {
  const config = readProviderConfig(environment, provider);
  if (providers) return providers[provider];

  if (provider === 'openai') {
    const { createOpenAIProvider }: typeof import('./openaiProvider') = require('./openaiProvider');
    return createOpenAIProvider(config);
  }

  const { createAnthropicProvider }: typeof import('./anthropicProvider') = require('./anthropicProvider');
  return createAnthropicProvider(config);
}

export function estimateCostUsd(
  inputTokens: number,
  outputTokens: number,
  config: CoachingProviderConfig,
): number {
  return (
    (inputTokens * config.inputPriceUsdPerMillionTokens +
      outputTokens * config.outputPriceUsdPerMillionTokens) /
    1_000_000
  );
}

export function estimateMaximumCoachingUsage(
  provider: CoachingProviderId,
  input: ProviderCoachingInput,
  config: CoachingProviderConfig,
): UsageReceipt {
  // A UTF-8 token cannot contain less than one byte. Reserving one token per byte,
  // plus the configured structured-output overhead, deliberately overestimates input.
  const inputTokens = Buffer.byteLength(input.systemPrompt, 'utf8') +
    Buffer.byteLength(input.userPrompt, 'utf8') +
    config.structuredOutputInputTokenOverhead;
  const outputTokens = config.maxOutputTokens;
  return {
    provider,
    model: config.model,
    inputTokens,
    outputTokens,
    estimatedCostUsd: estimateCostUsd(inputTokens, outputTokens, config),
  };
}

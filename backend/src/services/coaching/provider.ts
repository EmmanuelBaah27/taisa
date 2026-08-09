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
  respond(input: ProviderCoachingInput): Promise<ProviderCoachingResult>;
}

export interface CoachingProviderConfig {
  model: string;
  inputPriceUsdPerMillionTokens: number;
  outputPriceUsdPerMillionTokens: number;
}

type CoachingEnvironment = Record<string, string | undefined>;
type ProviderRegistry = Record<'openai' | 'anthropic', CoachingProvider>;

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

function readProviderConfig(
  environment: CoachingEnvironment,
  provider: 'openai' | 'anthropic',
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
  };
}

export function getConfiguredProvider(
  environment: CoachingEnvironment = process.env,
  providers?: ProviderRegistry,
): CoachingProvider {
  const configured = environment.TAISA_COACHING_PROVIDER?.trim();
  if (configured !== 'openai' && configured !== 'anthropic') {
    throw new Error('TAISA_COACHING_PROVIDER must be configured as openai or anthropic');
  }

  const config = readProviderConfig(environment, configured);
  if (providers) return providers[configured];

  if (configured === 'openai') {
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

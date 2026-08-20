import { colors } from '../../constants/theme';

export type LiquidGlassHierarchy = 'prominent' | 'standard' | 'subtle';
export type LiquidGlassTone = 'neutral' | 'accent' | 'destructive';
export type LiquidGlassShape = 'capsule' | 'circle' | 'rounded';
export type LiquidGlassMode = 'native' | 'fallback';

export interface LiquidGlassCapabilityInput {
  platform: string;
  nativeEnabled: boolean;
  apiAvailable: boolean;
  liquidGlassAvailable: boolean;
  reduceTransparency: boolean;
}

export interface LiquidGlassFallbackTokens {
  blurIntensity: number;
  backgroundColor: string;
  borderColor: string;
  sheenColors: readonly [string, string];
  shadowCasterColor: string;
  shadowColor: string;
  shadowOffsetY: number;
  shadowOpacity: number;
  shadowRadius: number;
}

export interface LiquidGlassAppearance {
  glassEffectStyle: 'regular' | 'clear';
  tintColor?: string;
  fallback: LiquidGlassFallbackTokens;
}

const TINTS: Record<LiquidGlassTone, string | undefined> = {
  neutral: undefined,
  accent: 'rgba(205,236,26,0.72)',
  destructive: 'rgba(198,0,0,0.72)',
};

const FALLBACK_BACKGROUND: Record<LiquidGlassTone, string> = {
  neutral: 'rgba(255,255,255,0.54)',
  accent: 'rgba(205,236,26,0.82)',
  destructive: 'rgba(198,0,0,0.82)',
};

const FALLBACK_BORDER: Record<LiquidGlassTone, string> = {
  neutral: 'rgba(15,16,16,0.10)',
  accent: 'rgba(119,135,0,0.18)',
  destructive: 'rgba(120,0,0,0.18)',
};

export function resolveLiquidGlassMode(input: LiquidGlassCapabilityInput): LiquidGlassMode {
  return input.platform === 'ios'
    && input.nativeEnabled
    && input.apiAvailable
    && input.liquidGlassAvailable
    && !input.reduceTransparency
    ? 'native'
    : 'fallback';
}

export function getLiquidGlassAppearance(
  hierarchy: LiquidGlassHierarchy,
  tone: LiquidGlassTone,
): LiquidGlassAppearance {
  const subtle = hierarchy === 'subtle';
  const neutralSubtle = subtle && tone === 'neutral';
  const neutralStandard = hierarchy === 'standard' && tone === 'neutral';
  const backgroundColor = neutralStandard
    ? 'rgba(255,255,255,0.38)'
    : neutralSubtle
      ? 'rgba(255,255,255,0.24)'
      : FALLBACK_BACKGROUND[tone];

  return {
    glassEffectStyle: subtle ? 'clear' : 'regular',
    tintColor: TINTS[tone],
    fallback: {
      blurIntensity: hierarchy === 'prominent' ? 78 : hierarchy === 'standard' ? 68 : 48,
      backgroundColor,
      borderColor: neutralStandard ? 'rgba(15,16,16,0.14)' : FALLBACK_BORDER[tone],
      sheenColors: neutralStandard
        ? ['rgba(255,255,255,0.62)', 'rgba(255,255,255,0.04)']
        : ['rgba(255,255,255,0.46)', 'rgba(255,255,255,0.06)'],
      shadowCasterColor: backgroundColor,
      shadowColor: colors.shadowSubtle,
      shadowOffsetY: hierarchy === 'prominent' ? 7 : hierarchy === 'standard' ? 6 : 4,
      shadowOpacity: hierarchy === 'prominent' ? 0.16 : hierarchy === 'standard' ? 0.12 : 0.08,
      shadowRadius: hierarchy === 'prominent' ? 18 : hierarchy === 'standard' ? 14 : 10,
    },
  };
}

export function resolveOptionalLiquidGlassModule<T>(
  enabled: boolean,
  loader: () => T,
): T | null {
  if (!enabled) return null;

  try {
    return loader();
  } catch {
    return null;
  }
}

import { colorTokens } from '../design-system/tokens';

export const colors = {
  background: colorTokens.surface.app,
  backgroundTransparent: colorTokens.native.transparentApp,
  surface: colorTokens.surface.elevated,
  surfaceElevated: colorTokens.surface.subtle,
  border: colorTokens.border.default,
  borderSubtle: colorTokens.overlay.separator,
  secondaryActionSurface: colorTokens.native.secondaryActionSurface,
  secondaryActionBorder: colorTokens.native.secondaryActionBorder,
  secondaryActionIcon: colorTokens.text.primary,
  shadowSubtle: colorTokens.native.shadow,
  recordingMark: colorTokens.native.recordingMark,

  // Primary (lime-500)
  accent: colorTokens.action.primary,
  accentMuted: colorTokens.native.accentMuted,
  accentGlow: colorTokens.native.accentGlow,

  // Semantic
  positive: colorTokens.status.success,
  positiveMuted: colorTokens.status.successSurface,
  warning: colorTokens.status.warning,
  warningMuted: colorTokens.status.warningSurface,
  error: colorTokens.status.danger,
  errorMuted: colorTokens.status.dangerSurface,
  info: colorTokens.status.info,

  // Text
  textPrimary: colorTokens.text.primary,
  textSecondary: colorTokens.text.secondary,
  textTertiary: colorTokens.text.tertiary,
  textAccent: colorTokens.native.accentText,

  // Momentum signals
  momentum: {
    accelerating: colorTokens.status.success,
    steady: colorTokens.status.info,
    stalling: colorTokens.status.warning,
    recovering: colorTokens.native.tealText,
  },

  // Sentiment
  sentiment: {
    'very-positive': colorTokens.status.success,
    positive: colorTokens.native.positiveLight,
    neutral: colorTokens.status.info,
    challenging: colorTokens.status.warning,
    difficult: colorTokens.status.danger,
  },
};

export const spacing = {
  xs: 4,
  sm: 8,
  md: 16,
  lg: 24,
  xl: 32,
  xxl: 48,
};

export const radius = {
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24,
  full: 9999,
};

export const fontSize = {
  xs: 11,
  sm: 13,
  base: 15,
  md: 17,
  lg: 20,
  xl: 24,
  xxl: 30,
  display: 38,
};

export const fontWeight = {
  regular: '400' as const,
  medium: '500' as const,
  semibold: '600' as const,
  bold: '700' as const,
};

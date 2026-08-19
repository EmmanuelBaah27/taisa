export const colors = {
  background: '#ffffff',
  backgroundTransparent: 'rgba(255,255,255,0)',
  surface: '#ffffff',
  surfaceElevated: '#f9f9f9',
  border: '#e6e6e6',
  borderSubtle: 'rgba(6,7,7,0.08)',
  secondaryActionSurface: 'rgba(255,255,255,0.18)',
  secondaryActionBorder: 'rgba(23,23,23,0.06)',
  secondaryActionIcon: '#0F1010',
  shadowSubtle: '#000000',

  // Primary (lime-500)
  accent: '#cdec1a',
  accentMuted: '#edfbca',
  accentGlow: 'rgba(205,236,26,0.3)',

  // Semantic
  positive: '#04851a',
  positiveMuted: '#e7f9e9',
  warning: '#e46300',
  warningMuted: '#fcf2e8',
  error: '#c60000',
  errorMuted: '#fff0ea',
  info: '#0c79e6',

  // Text
  textPrimary: '#060707',
  textSecondary: '#5f646a',
  textTertiary: '#898989',
  textAccent: '#778700',

  // Momentum signals
  momentum: {
    accelerating: '#04851a',
    steady: '#0c79e6',
    stalling: '#e46300',
    recovering: '#004148',
  },

  // Sentiment
  sentiment: {
    'very-positive': '#04851a',
    positive: '#86e091',
    neutral: '#0c79e6',
    challenging: '#e46300',
    difficult: '#c60000',
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

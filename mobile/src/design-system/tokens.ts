import registry from '../../design-system/tokens.json';

type FontWeight = '400' | '500' | '600' | '700';

interface TypographyToken {
  fontFamily: string;
  fontSize: number;
  fontWeight: FontWeight;
  lineHeight: number;
  letterSpacing: number;
}

interface ColorContract {
  surface: Record<string, string>;
  text: Record<string, string>;
  border: Record<string, string>;
  action: Record<string, string>;
  status: Record<string, string>;
  overlay: Record<string, string>;
  native: Record<string, string>;
}

const checkedColors = registry.color satisfies ColorContract;
const checkedTypography = registry.typography;

function assertTypographyContract(
  value: Record<string, Omit<TypographyToken, 'fontWeight'> & { fontWeight: string }>,
): asserts value is Record<string, TypographyToken> {
  const supportedWeights = new Set<FontWeight>(['400', '500', '600', '700']);
  for (const [role, token] of Object.entries(value)) {
    if (!supportedWeights.has(token.fontWeight as FontWeight)) {
      throw new Error(`Unsupported font weight for typography role ${role}: ${token.fontWeight}`);
    }
  }
}

assertTypographyContract(checkedTypography);

export const colorTokens = Object.freeze(checkedColors);
export const typographyTokens = Object.freeze(checkedTypography);

export type ColorFamily = keyof typeof colorTokens;
export type ColorRole<Family extends ColorFamily> = keyof (typeof colorTokens)[Family];
export type TypographyRole = keyof typeof typographyTokens;

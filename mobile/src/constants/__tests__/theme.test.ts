import { colors } from '../theme';

describe('brand color tokens', () => {
  test('uses the approved primary color and derived glow', () => {
    expect(colors.accent).toBe('#dede0f');
    expect(colors.accentGlow).toBe('rgba(222,222,15,0.3)');
  });
});

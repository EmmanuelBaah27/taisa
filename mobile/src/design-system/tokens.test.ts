import { colorTokens, typographyTokens } from './tokens';

describe('semantic design-system tokens', () => {
  it('exposes the approved typography roles at readable sizes', () => {
    expect(typographyTokens.body.fontSize).toBe(16);
    expect(typographyTokens.label.fontSize).toBe(14);
    expect(typographyTokens.metadata.fontSize).toBe(12);
    expect(Object.keys(typographyTokens)).toEqual([
      'display',
      'heading',
      'subheading',
      'body',
      'bodyStrong',
      'label',
      'labelStrong',
      'metadata',
      'metadataStrong',
    ]);
  });

  it('exposes semantic color families required by Product UI', () => {
    expect(colorTokens.text).toHaveProperty('primary');
    expect(colorTokens.surface).toHaveProperty('app');
    expect(colorTokens.action).toHaveProperty('primary');
    expect(colorTokens.status).toHaveProperty('danger');
  });
});

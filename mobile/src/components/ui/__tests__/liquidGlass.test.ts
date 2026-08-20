import {
  getLiquidGlassAppearance,
  resolveLiquidGlassMode,
  resolveOptionalLiquidGlassModule,
} from '../liquidGlass';

describe('liquid glass capability and appearance', () => {
  const supported = {
    platform: 'ios',
    nativeEnabled: true,
    apiAvailable: true,
    liquidGlassAvailable: true,
    reduceTransparency: false,
  } as const;

  test('uses native glass only when every iOS capability is available', () => {
    expect(resolveLiquidGlassMode(supported)).toBe('native');
    expect(resolveLiquidGlassMode({ ...supported, platform: 'android' })).toBe('fallback');
    expect(resolveLiquidGlassMode({ ...supported, nativeEnabled: false })).toBe('fallback');
    expect(resolveLiquidGlassMode({ ...supported, apiAvailable: false })).toBe('fallback');
    expect(resolveLiquidGlassMode({ ...supported, liquidGlassAvailable: false })).toBe('fallback');
  });

  test('honors reduced transparency even when native glass exists', () => {
    expect(resolveLiquidGlassMode({ ...supported, reduceTransparency: true })).toBe('fallback');
  });

  test('maps semantic prominence and tint without changing layout', () => {
    expect(getLiquidGlassAppearance('prominent', 'accent')).toMatchObject({
      glassEffectStyle: 'regular',
      tintColor: 'rgba(205,236,26,0.72)',
    });
    expect(getLiquidGlassAppearance('prominent', 'destructive')).toMatchObject({
      glassEffectStyle: 'regular',
      tintColor: 'rgba(198,0,0,0.72)',
    });
    expect(getLiquidGlassAppearance('subtle', 'neutral')).toMatchObject({
      glassEffectStyle: 'clear',
      tintColor: undefined,
    });
  });

  test('gives every hierarchy a deliberate neutral ambient elevation', () => {
    expect(getLiquidGlassAppearance('prominent', 'neutral').fallback).toMatchObject({
      shadowOffsetY: 7,
      shadowOpacity: 0.16,
      shadowRadius: 18,
    });
    expect(getLiquidGlassAppearance('standard', 'neutral').fallback).toMatchObject({
      shadowCasterColor: 'rgba(255,255,255,0.54)',
      shadowOffsetY: 6,
      shadowOpacity: 0.12,
      shadowRadius: 14,
    });
    expect(getLiquidGlassAppearance('subtle', 'neutral').fallback).toMatchObject({
      shadowOffsetY: 4,
      shadowOpacity: 0.08,
      shadowRadius: 10,
    });
  });

  test('does not evaluate or crash on an unavailable optional module', () => {
    const loader = jest.fn(() => {
      throw new Error('missing native module');
    });

    expect(resolveOptionalLiquidGlassModule(false, loader)).toBeNull();
    expect(loader).not.toHaveBeenCalled();
    expect(resolveOptionalLiquidGlassModule(true, loader)).toBeNull();
  });
});

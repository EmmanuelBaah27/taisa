import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { getButtonLiquidGlassAppearance } from '../Button';

describe('Button liquid glass migration', () => {
  test('maps every semantic variant to the approved hierarchy and tone', () => {
    expect(getButtonLiquidGlassAppearance('primary')).toEqual({ hierarchy: 'prominent', tone: 'accent' });
    expect(getButtonLiquidGlassAppearance('secondary')).toEqual({ hierarchy: 'standard', tone: 'neutral' });
    expect(getButtonLiquidGlassAppearance('tertiary')).toEqual({ hierarchy: 'subtle', tone: 'neutral' });
    expect(getButtonLiquidGlassAppearance('destructive')).toEqual({ hierarchy: 'prominent', tone: 'destructive' });
    expect(getButtonLiquidGlassAppearance('secondary-destructive')).toEqual({ hierarchy: 'standard', tone: 'destructive' });
    expect(getButtonLiquidGlassAppearance('tertiary-destructive')).toEqual({ hierarchy: 'subtle', tone: 'destructive' });
  });

  test('preserves the approved button geometry and composes the shared surface', () => {
    const source = readFileSync(resolve(__dirname, '../Button.tsx'), 'utf8');

    expect(source).toContain("default: 'h-[40px] px-5'");
    expect(source).toContain("sm:      'h-[32px] px-3'");
    expect(source).toContain("icon:    'h-[40px] w-[40px] p-[10px]'");
    expect(source).toContain("'icon-lg': 'h-[56px] w-[56px] p-4'");
    expect(source).toContain('<LiquidGlassPressable');
    expect(source).not.toContain('useSharedValue');
  });
});

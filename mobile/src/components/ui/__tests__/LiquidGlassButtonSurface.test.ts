import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import {
  getLiquidGlassShapeStyle,
  getLiquidGlassPressScale,
} from '../LiquidGlassButtonSurface';

describe('LiquidGlassButtonSurface', () => {
  test('maps the approved shapes without owning control geometry', () => {
    expect(getLiquidGlassShapeStyle('capsule')).toEqual({ borderRadius: 9999 });
    expect(getLiquidGlassShapeStyle('circle')).toEqual({ borderRadius: 9999, aspectRatio: 1 });
    expect(getLiquidGlassShapeStyle('rounded')).toEqual({ borderRadius: 16 });
  });

  test('uses restrained fallback feedback and no spatial reduced-motion feedback', () => {
    expect(getLiquidGlassPressScale(1, false, false)).toBe(0.97);
    expect(getLiquidGlassPressScale(1, true, false)).toBe(1);
    expect(getLiquidGlassPressScale(1, false, true)).toBe(1);
  });

  test('keeps the press-scale helper callable from the UI-thread animated style', () => {
    const source = readFileSync(
      resolve(__dirname, '../LiquidGlassButtonSurface.tsx'),
      'utf8',
    );

    expect(source).toMatch(
      /function getLiquidGlassPressScale\([\s\S]*?\): number \{\s*'worklet';/,
    );
  });

  test('mounts one interactive native surface without opacity animation or a nested pressable', () => {
    const source = readFileSync(
      resolve(__dirname, '../LiquidGlassButtonSurface.tsx'),
      'utf8',
    );

    expect(source).toContain('isInteractive');
    expect(source).toContain('NativeGlassView');
    expect(source).toContain("process.env.NODE_ENV !== 'test'");
    expect(source).not.toMatch(/<Pressable|<Touchable/);
    expect(source).not.toMatch(/NativeGlassView[\s\S]{0,300}opacity/);
  });

  test('separates unclipped elevation from the clipped glass material', () => {
    const source = readFileSync(
      resolve(__dirname, '../LiquidGlassButtonSurface.tsx'),
      'utf8',
    );

    expect(source).toContain("testID={testID ? `${testID}-elevation` : 'liquid-glass-elevation'}");
    expect(source).toMatch(/shadowRadius: appearance\.fallback\.shadowRadius/);
    expect(source).toMatch(/shadowOffset: \{ width: 0, height: appearance\.fallback\.shadowOffsetY \}/);
    expect(source).toMatch(/overflow: 'visible'/);
    expect(source).toMatch(/NativeGlassView[\s\S]*overflow: 'hidden'/);
    expect(source).toMatch(/NativeGlassView[\s\S]*borderColor: appearance\.fallback\.borderColor/);
    expect(source).toMatch(/key="fallback-material"[\s\S]*overflow: 'hidden'/);
  });

  test('centres children inside both native and fallback glass materials', () => {
    const source = readFileSync(
      resolve(__dirname, '../LiquidGlassButtonSurface.tsx'),
      'utf8',
    );

    expect(source.match(/alignItems: 'center', justifyContent: 'center'/g)).toHaveLength(2);
  });
});

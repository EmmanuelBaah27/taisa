import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { getLiquidGlassPressableShape } from '../LiquidGlassPressable';

describe('LiquidGlassPressable', () => {
  test('keeps shape selection explicit', () => {
    expect(getLiquidGlassPressableShape()).toBe('capsule');
    expect(getLiquidGlassPressableShape('circle')).toBe('circle');
    expect(getLiquidGlassPressableShape('rounded')).toBe('rounded');
  });

  test('owns one semantic pressable and one shared glass surface', () => {
    const source = readFileSync(resolve(__dirname, '../LiquidGlassPressable.tsx'), 'utf8');

    expect(source.match(/<Pressable/g)).toHaveLength(1);
    expect(source.match(/<LiquidGlassButtonSurface/g)).toHaveLength(1);
    expect(source).toContain('accessibilityRole="button"');
    expect(source).toContain('withTiming(1, { duration: 100 })');
    expect(source).toContain('withSpring(0, { damping: 24, stiffness: 360 })');
  });
});

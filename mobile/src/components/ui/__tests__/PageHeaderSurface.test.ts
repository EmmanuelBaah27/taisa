import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

describe('PageHeaderSurface', () => {
  const componentPath = resolve(__dirname, '../PageHeaderSurface.tsx');
  const source = existsSync(componentPath) ? readFileSync(componentPath, 'utf8') : '';

  test('provides a solid static header with a visible bottom fade', () => {
    expect(source).not.toContain('<BlurView');
    expect(source).toContain('<LinearGradient');
    expect(source).toContain('backgroundColor: colors.background');
    expect(source).toContain('colors.backgroundTransparent');
    expect(source).toContain("pointerEvents=\"box-none\"");
    expect(source).toContain('position: \'absolute\'');
    expect(source).not.toContain('useAnimatedStyle');
  });

  test('keeps existing title and workspace geometry available as scroll insets', () => {
    expect(source).toContain("variant === 'workspace'");
    expect(source).toContain('paddingTop + 66');
    expect(source).toContain('paddingTop + 44');
  });
});

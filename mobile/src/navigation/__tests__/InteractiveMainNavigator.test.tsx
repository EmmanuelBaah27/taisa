import fs from 'node:fs';
import path from 'node:path';
describe('InteractiveMainNavigator', () => {
  test('keeps all three pages warm on one clipped track so a swipe never reveals empty space', () => {
    const source = fs.readFileSync(path.resolve(__dirname, '../InteractiveMainNavigator.tsx'), 'utf8');
    expect(source).toMatch(/testID="main-scene-viewport"/);
    expect(source).toMatch(/testID="main-scene-track"/);
    expect(source).toMatch(/state\.routes\.map/);
    expect(source).toMatch(/left: \(routeIndex - activeIndex\) \* viewportWidth/);
    expect(source).toMatch(/cancelsTouchesInView\(true\)/);
  });

  test('uses the route-authoritative custom navigator boundary without a native pager', () => {
    const source = fs.readFileSync(
      path.resolve(__dirname, '../InteractiveMainNavigator.tsx'),
      'utf8',
    );

    expect(source).toMatch(/useNavigationBuilder<[\s\S]*?>\(TabRouter/);
    expect(source).toMatch(/withLayoutContext/);
    expect(source).not.toMatch(/react-native-pager-view/);
  });
});

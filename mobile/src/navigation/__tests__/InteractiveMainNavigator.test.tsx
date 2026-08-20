import fs from 'node:fs';
import path from 'node:path';

describe('InteractiveMainNavigator', () => {
  const source = fs.readFileSync(
    path.resolve(__dirname, '../InteractiveMainNavigator.tsx'),
    'utf8',
  );

  test('uses the native iOS pager while keeping Expo Router authoritative', () => {
    expect(source).toMatch(/useNavigationBuilder<[\s\S]*?>\(TabRouter/);
    expect(source).toMatch(/withLayoutContext/);
    expect(source).toMatch(/from 'react-native-pager-view'/);
    expect(source).toMatch(/onPageScroll=/);
    expect(source).toMatch(/onPageSelected=/);
    expect(source).not.toMatch(/Gesture\.Pan\(\)/);
  });

  test('keeps the navigation and voice control outside the moving pager', () => {
    expect(source).toMatch(
      /<AnimatedPagerView[\s\S]*<\/AnimatedPagerView>\s*<BottomNavBar \/>\s*<VoiceButton \/>/,
    );
  });

  test('drives capsule progress from the native page offset on the UI thread', () => {
    expect(source).toMatch(/'worklet';[\s\S]*event\.position \+ event\.offset/);
    expect(source).toMatch(/swipeProgress\.value = Math\.min\(Math\.abs\(delta\), 1\)/);
    expect(source).toMatch(/swipeToIndex\.value = delta < 0/);
  });

  test('uses the same native pager for taps and direct route selection', () => {
    expect(source).toMatch(/pagerRef\.current\?\.setPage\(destinationIndex\)/);
    expect(source).toMatch(/setPageWithoutAnimation\(destinationIndex\)/);
    expect(source).toMatch(/CommonActions\.navigate/);
  });
});

import fs from 'node:fs';
import path from 'node:path';

describe('InteractiveMainNavigator', () => {
  const source = fs.readFileSync(
    path.resolve(__dirname, '../InteractiveMainNavigator.tsx'),
    'utf8',
  );

  test('uses the built-in native scroll pager while keeping Expo Router authoritative', () => {
    expect(source).toMatch(/useNavigationBuilder<[\s\S]*?>\(TabRouter/);
    expect(source).toMatch(/withLayoutContext/);
    expect(source).not.toMatch(/from 'react-native-pager-view'/);
    expect(source).toMatch(/<Animated\.ScrollView/);
    expect(source).toMatch(/horizontal/);
    expect(source).toMatch(/pagingEnabled/);
    expect(source).not.toMatch(/Gesture\.Pan\(\)/);
  });

  test('keeps the navigation and voice control outside the moving pager', () => {
    expect(source).toMatch(
      /<Animated\.ScrollView[\s\S]*<\/Animated\.ScrollView>\s*<BottomNavBar \/>\s*<VoiceButton \/>/,
    );
  });

  test('drives capsule progress from the native content offset on the UI thread', () => {
    expect(source).toMatch(/'worklet';[\s\S]*event\.contentOffset\.x \/ pageWidth/);
    expect(source).toMatch(/swipeProgress\.value = Math\.min\(Math\.abs\(delta\), 1\)/);
    expect(source).toMatch(/swipeToIndex\.value = delta < 0/);
  });

  test('uses the same native scroll pager for taps and direct route selection', () => {
    expect(source).toMatch(/scrollRef\.current\?\.scrollTo\(\{[\s\S]*animated: true/);
    expect(source).toMatch(/scrollRef\.current\?\.scrollTo\(\{[\s\S]*animated: false/);
    expect(source).toMatch(/CommonActions\.navigate/);
  });

  test('holds the destination position until route settlement completes', () => {
    expect(source).toMatch(
      /swipeFromIndex\.value = destinationIndex;\s*swipeToIndex\.value = destinationIndex;\s*swipeProgress\.value = 0;\s*swipeInteracting\.value = 1;/,
    );
  });

  test('crossfades a non-adjacent tab directly without scrolling through Home', () => {
    expect(source).toContain('const nonAdjacent = Math.abs(destinationIndex - state.index) > 1');
    expect(source).toMatch(/jumpDirectlyToPage[\s\S]*scrollTo\(\{ x: destinationIndex \* pageWidth, animated: false \}\)/);
    expect(source).toContain('runOnJS(jumpDirectlyToPage)(destinationIndex)');
    expect(source).toContain('directTransition.value');
    expect(source).toContain('directPageOpacity.value');
  });
});

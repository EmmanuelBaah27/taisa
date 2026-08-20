import fs from 'node:fs';
import path from 'node:path';

describe('InteractiveMainNavigator', () => {
  const source = fs.readFileSync(
    path.resolve(__dirname, '../InteractiveMainNavigator.tsx'),
    'utf8',
  );
  const bottomNavSource = fs.readFileSync(
    path.resolve(__dirname, '../../components/ui/BottomNavBar.tsx'),
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

  test('crossfades every tapped destination without horizontal page travel', () => {
    expect(source).toMatch(/scrollRef\.current\?\.scrollTo\(\{[\s\S]*animated: false/);
    expect(source).toMatch(/CommonActions\.navigate/);
    expect(source).not.toContain('const nonAdjacent');
    expect(source).not.toMatch(/scrollRef\.current\?\.scrollTo\(\{ x: destinationIndex \* pageWidth, animated: true \}\)/);
    expect(source).toMatch(/const navigate[\s\S]*directTransition\.value = 1[\s\S]*directPageOpacity\.value = withTiming\(0/);
  });

  test('holds the destination position until route settlement completes', () => {
    expect(source).toMatch(
      /swipeFromIndex\.value = destinationIndex;\s*swipeToIndex\.value = destinationIndex;\s*swipeProgress\.value = 0;\s*swipeInteracting\.value = 1;/,
    );
  });

  test('keeps tap-driven page commits free of haptics', () => {
    expect(source).not.toContain('playInteractionHaptic');
  });

  test('uses the established direct fade timings for tapped destinations', () => {
    expect(source).toMatch(/jumpDirectlyToPage[\s\S]*scrollTo\(\{ x: destinationIndex \* pageWidth, animated: false \}\)/);
    expect(source).toContain('runOnJS(jumpDirectlyToPage)(destinationIndex)');
    expect(source).toContain('withTiming(0, { duration: 90 }');
    expect(source).toContain('withTiming(1, { duration: 170 }');
    expect(source).toContain('directTransition.value');
    expect(source).toContain('directPageOpacity.value');
  });

  test('drives tapped capsule travel through the same continuous progress path as a swipe', () => {
    expect(source).toContain('withSpring');
    expect(source).toMatch(/swipeProgress\.value = withSpring\(1/);
    expect(source).not.toMatch(/swipeProgress\.value = withTiming\(1/);
    expect(bottomNavSource).toMatch(/pagePosition[\s\S]*interaction\.progress\.value/);
  });
});

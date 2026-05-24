import Animated, {
  useAnimatedStyle,
  interpolate,
  SharedValue,
} from 'react-native-reanimated';
import { useWindowDimensions } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

// Must match VoiceButton.tsx exactly:
//   paddingHorizontal: 44 (×2 = 88) + icon width 24 = 112
//   paddingVertical: 16 (×2 = 32) + icon height 24 = 56
//   borderRadius: 48
//   bottom: insets.bottom + 16
const PILL_W = 112;
const PILL_H = 56;
const PILL_RADIUS = 48;

interface MorphSurfaceProps {
  progress: SharedValue<number>;
}

export function MorphSurface({ progress }: MorphSurfaceProps) {
  const insets = useSafeAreaInsets();
  const { width: screenW, height: screenH } = useWindowDimensions();

  const style = useAnimatedStyle(() => ({
    position: 'absolute',
    backgroundColor: '#ffffff',
    width: interpolate(progress.value, [0, 1], [PILL_W, screenW]),
    height: interpolate(progress.value, [0, 1], [PILL_H, screenH]),
    borderRadius: interpolate(progress.value, [0, 1], [PILL_RADIUS, 0]),
    bottom: interpolate(progress.value, [0, 1], [insets.bottom + 16, 0]),
    left: interpolate(progress.value, [0, 1], [(screenW - PILL_W) / 2, 0]),
  }));

  return <Animated.View style={style} />;
}

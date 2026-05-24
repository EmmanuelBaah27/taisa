import Animated, {
  useAnimatedStyle,
  interpolate,
  interpolateColor,
  SharedValue,
} from 'react-native-reanimated';
import { useWindowDimensions } from 'react-native';

// Must match VoiceButton.tsx exactly:
//   paddingHorizontal: 44 (×2 = 88) + icon width 24 = 112
//   paddingVertical: 16 (×2 = 32) + icon height 24 = 56
//   borderRadius: 48
//   bottom: insets.bottom + 16  (pillBottom = insets.bottom + 16, passed from parent)
const PILL_W = 112;
const PILL_H = 56;
const PILL_RADIUS = 48;

// Must match VoiceButton's backgroundColor exactly so the morph looks like
// the button itself expanding.
const BUTTON_COLOR = '#cdec1a';
const SCREEN_COLOR = '#ffffff';

interface MorphSurfaceProps {
  progress: SharedValue<number>;
  // Distance from screen bottom to the pill's bottom edge.
  // Pass insets.bottom + 16 from the parent — avoids reading stale insets inside transparentModal.
  pillBottom: number;
}

export function MorphSurface({ progress, pillBottom }: MorphSurfaceProps) {
  const { width: screenW, height: screenH } = useWindowDimensions();

  const scaleX0 = PILL_W / screenW;
  const scaleY0 = PILL_H / screenH;

  const pillCenterY = screenH - pillBottom - PILL_H / 2;
  const translateY0 = pillCenterY - screenH / 2;

  // Border radius in element-space so visual radius ≈ PILL_RADIUS at progress=0.
  // At progress=1 use 1 (NOT 0) — animating layout values to 0 triggers a Fabric flicker bug.
  const borderRadius0 = PILL_RADIUS / scaleX0;

  const animatedStyle = useAnimatedStyle(() => {
    const sx = interpolate(progress.value, [0, 1], [scaleX0, 1]);
    const sy = interpolate(progress.value, [0, 1], [scaleY0, 1]);
    const ty = interpolate(progress.value, [0, 1], [translateY0, 0]);
    const br = interpolate(progress.value, [0, 1], [borderRadius0, 1]);

    // Transition from button colour → screen colour in the first 30% of the open
    // (and back in the last 30% of the close) so the morph looks like the button itself expanding.
    const bg = interpolateColor(progress.value, [0, 0.3], [BUTTON_COLOR, SCREEN_COLOR]);

    return {
      transform: [{ translateY: ty }, { scaleX: sx }, { scaleY: sy }],
      borderRadius: br,
      backgroundColor: bg,
    };
  });

  return (
    <Animated.View
      style={[
        { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 },
        animatedStyle,
      ]}
      pointerEvents="none"
    />
  );
}

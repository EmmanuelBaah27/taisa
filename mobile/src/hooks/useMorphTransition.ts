import {
  useSharedValue,
  withTiming,
  Easing,
  SharedValue,
} from 'react-native-reanimated';
import { useWindowDimensions } from 'react-native';

// Ease-out expo: starts fast, decelerates smoothly — no bounce.
const OPEN_EASING = Easing.bezier(0.22, 1, 0.36, 1);
const OPEN_DURATION = 380;
const CLOSE_EASING = Easing.bezier(0.3, 0, 1, 1);
const CLOSE_DURATION = 300;

export interface SlideTransition {
  translateY: SharedValue<number>;
  open: () => void;
  close: () => void;
}

export function useMorphTransition(): SlideTransition {
  const { height: screenH } = useWindowDimensions();
  const translateY = useSharedValue(screenH);

  function open() {
    translateY.value = screenH;
    translateY.value = withTiming(0, { duration: OPEN_DURATION, easing: OPEN_EASING });
  }

  function close() {
    translateY.value = withTiming(screenH, { duration: CLOSE_DURATION, easing: CLOSE_EASING });
  }

  return { translateY, open, close };
}

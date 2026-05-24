import {
  useSharedValue,
  withSpring,
  withTiming,
  withDelay,
  Easing,
  SharedValue,
} from 'react-native-reanimated';

const SPRING_OPEN = { damping: 22, stiffness: 110 };

// Close: 280ms ease-in — feels decisive, no bounce.
// Easing.bezier(0.3, 0, 1, 1) accelerates throughout, like a sheet snapping away.
const CLOSE_DURATION = 280;
const CLOSE_EASING = Easing.bezier(0.3, 0, 1, 1);

export interface MorphTransition {
  progress: SharedValue<number>;
  contentOpacity: SharedValue<number>;
  open: () => void;
  close: () => void;
}

export function useMorphTransition(): MorphTransition {
  const progress = useSharedValue(0);
  const contentOpacity = useSharedValue(0);

  function open() {
    progress.value = withSpring(1, SPRING_OPEN);
    contentOpacity.value = withDelay(60, withTiming(1, { duration: 180 }));
  }

  function close() {
    contentOpacity.value = withTiming(0, { duration: 100 });
    progress.value = withTiming(0, { duration: CLOSE_DURATION, easing: CLOSE_EASING });
  }

  return { progress, contentOpacity, open, close };
}

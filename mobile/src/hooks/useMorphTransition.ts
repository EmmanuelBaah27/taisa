import {
  useSharedValue,
  withSpring,
  withTiming,
  withDelay,
  runOnJS,
  SharedValue,
} from 'react-native-reanimated';

const SPRING_OPEN = { damping: 28, stiffness: 260 };
const SPRING_CLOSE = { damping: 32, stiffness: 300 };

export interface MorphTransition {
  progress: SharedValue<number>;
  contentOpacity: SharedValue<number>;
  open: () => void;
  close: (onDone: () => void) => void;
}

export function useMorphTransition(): MorphTransition {
  const progress = useSharedValue(0);
  const contentOpacity = useSharedValue(0);

  function open() {
    progress.value = withSpring(1, SPRING_OPEN);
    contentOpacity.value = withDelay(60, withTiming(1, { duration: 180 }));
  }

  function close(onDone: () => void) {
    contentOpacity.value = withTiming(0, { duration: 140 }, () => {
      progress.value = withSpring(0, SPRING_CLOSE, () => {
        runOnJS(onDone)();
      });
    });
  }

  return { progress, contentOpacity, open, close };
}

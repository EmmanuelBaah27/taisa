import {
  useSharedValue,
  withTiming,
  Easing,
  SharedValue,
  useReducedMotion,
  runOnJS,
} from 'react-native-reanimated';
import { useWindowDimensions } from 'react-native';
import type { ChatCardSource } from '../navigation/chatCardExpansion';
import {
  getChatCardInitialTransform,
  isChatCardSourceViewportCurrent,
} from '../navigation/chatCardExpansion';

// Ease-out expo: starts fast, decelerates smoothly — no bounce.
const OPEN_EASING = Easing.bezier(0.22, 1, 0.36, 1);
const OPEN_DURATION = 380;
export interface SlideTransition {
  translateX: SharedValue<number>;
  translateY: SharedValue<number>;
  scaleX: SharedValue<number>;
  scaleY: SharedValue<number>;
  borderRadius: SharedValue<number>;
  open: () => void;
  close: (onFinished: () => void) => void;
}

export function useMorphTransition(source: ChatCardSource | null): SlideTransition {
  const viewport = useWindowDimensions();
  const reduceMotion = useReducedMotion();
  const initial = reduceMotion || source === null || !isChatCardSourceViewportCurrent(source, viewport)
    ? null
    : getChatCardInitialTransform(source.frame, viewport);
  const translateX = useSharedValue(initial?.translateX ?? 0);
  const translateY = useSharedValue(initial?.translateY ?? 0);
  const scaleX = useSharedValue(initial?.scaleX ?? 1);
  const scaleY = useSharedValue(initial?.scaleY ?? 1);
  const borderRadius = useSharedValue(initial === null ? 0 : 24);

  function open() {
    translateX.value = withTiming(0, { duration: OPEN_DURATION, easing: OPEN_EASING });
    translateY.value = withTiming(0, { duration: OPEN_DURATION, easing: OPEN_EASING });
    scaleX.value = withTiming(1, { duration: OPEN_DURATION, easing: OPEN_EASING });
    scaleY.value = withTiming(1, { duration: OPEN_DURATION, easing: OPEN_EASING });
    borderRadius.value = withTiming(0, { duration: OPEN_DURATION, easing: OPEN_EASING });
  }

  function close(onFinished: () => void) {
    if (initial === null) {
      onFinished();
      return;
    }
    const options = { duration: OPEN_DURATION, easing: OPEN_EASING };
    translateX.value = withTiming(initial.translateX, options);
    translateY.value = withTiming(initial.translateY, options);
    scaleX.value = withTiming(initial.scaleX, options);
    scaleY.value = withTiming(initial.scaleY, options);
    borderRadius.value = withTiming(24, options, (finished) => {
      if (finished) runOnJS(onFinished)();
    });
  }

  return { translateX, translateY, scaleX, scaleY, borderRadius, open, close };
}

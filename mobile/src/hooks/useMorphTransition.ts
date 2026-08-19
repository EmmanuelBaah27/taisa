import {
  useSharedValue,
  withTiming,
  Easing,
  SharedValue,
  useReducedMotion,
  runOnJS,
  useDerivedValue,
  withDelay,
} from 'react-native-reanimated';
import { useWindowDimensions } from 'react-native';
import { useRef } from 'react';
import type { ChatCardSource } from '../navigation/chatCardExpansion';
import {
  getClosingChatShellOpacity,
  getChatCardInitialTransform,
  isChatCardSourceViewportCurrent,
} from '../navigation/chatCardExpansion';

// Ease-out expo: starts fast, decelerates smoothly — no bounce.
const OPEN_EASING = Easing.bezier(0.22, 1, 0.36, 1);
const OPEN_DURATION = 380;
const CONTENT_REVEAL_DELAY = 190;
const CONTENT_REVEAL_DURATION = 150;
const CONTENT_HIDE_DURATION = 100;
export interface SlideTransition {
  translateX: SharedValue<number>;
  translateY: SharedValue<number>;
  scaleX: SharedValue<number>;
  scaleY: SharedValue<number>;
  borderRadius: SharedValue<number>;
  shellOpacity: SharedValue<number>;
  contentOpacity: SharedValue<number>;
  contentTranslateY: SharedValue<number>;
  open: () => void;
  revealContent: () => void;
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
  const closeProgress = useSharedValue(0);
  const shellOpacity = useDerivedValue(() => getClosingChatShellOpacity(closeProgress.value));
  const contentOpacity = useSharedValue(initial === null ? 1 : 0);
  const contentTranslateY = useSharedValue(initial === null ? 0 : 8);
  const contentRevealStarted = useRef(initial === null);

  function open() {
    translateX.value = withTiming(0, { duration: OPEN_DURATION, easing: OPEN_EASING });
    translateY.value = withTiming(0, { duration: OPEN_DURATION, easing: OPEN_EASING });
    scaleX.value = withTiming(1, { duration: OPEN_DURATION, easing: OPEN_EASING });
    scaleY.value = withTiming(1, { duration: OPEN_DURATION, easing: OPEN_EASING });
    borderRadius.value = withTiming(0, { duration: OPEN_DURATION, easing: OPEN_EASING });
    closeProgress.value = 0;
  }

  function revealContent() {
    if (contentRevealStarted.current) return;
    contentRevealStarted.current = true;
    const options = { duration: CONTENT_REVEAL_DURATION, easing: OPEN_EASING };
    contentOpacity.value = withDelay(CONTENT_REVEAL_DELAY, withTiming(1, options));
    contentTranslateY.value = withDelay(CONTENT_REVEAL_DELAY, withTiming(0, options));
  }

  function close(onFinished: () => void) {
    if (initial === null) {
      onFinished();
      return;
    }
    const options = { duration: OPEN_DURATION, easing: OPEN_EASING };
    contentOpacity.value = withTiming(0, { duration: CONTENT_HIDE_DURATION, easing: OPEN_EASING });
    contentTranslateY.value = withTiming(4, { duration: CONTENT_HIDE_DURATION, easing: OPEN_EASING });
    translateX.value = withTiming(initial.translateX, options);
    translateY.value = withTiming(initial.translateY, options);
    scaleX.value = withTiming(initial.scaleX, options);
    scaleY.value = withTiming(initial.scaleY, options);
    borderRadius.value = withTiming(24, options);
    closeProgress.value = withTiming(1, options, (finished) => {
      if (finished) runOnJS(onFinished)();
    });
  }

  return {
    translateX,
    translateY,
    scaleX,
    scaleY,
    borderRadius,
    shellOpacity,
    contentOpacity,
    contentTranslateY,
    open,
    revealContent,
    close,
  };
}

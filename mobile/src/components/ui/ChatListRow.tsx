import { createRef, useEffect, useRef, useState } from 'react';
import {
  AccessibilityInfo,
  Animated,
  Easing,
  Pressable,
  type PressableProps,
  Text,
  View,
} from 'react-native';

import { colors } from '../../constants/theme';
import type { ChatCardFrame } from '../../navigation/chatCardExpansion';
import { Icon } from './Icon';

export interface ChatListRowProps {
  title: string;
  preview: string;
  needsAttention?: boolean;
  onOpen(frame: ChatCardFrame | null): void;
}

export const CHAT_LIST_ROW_MOTION = {
  pressedScale: 0.97,
  pressDuration: 100,
  releaseDuration: 140,
} as const;

export function createOpenOnce(onOpen: ChatListRowProps['onOpen']) {
  let opened = false;
  return (frame: ChatCardFrame | null) => {
    if (opened) return;
    opened = true;
    onOpen(frame);
    setTimeout(() => { opened = false; }, 750);
  };
}

interface ChatListRowSurfaceProps extends ChatListRowProps {
  onPressIn?: PressableProps['onPressIn'];
  onPressOut?: PressableProps['onPressOut'];
}

export function ChatListRowSurface({
  title,
  preview,
  needsAttention = false,
  onOpen,
  onPressIn,
  onPressOut,
}: ChatListRowSurfaceProps) {
  const rowRef = createRef<View>();
  let measuredFrame: ChatCardFrame | null | undefined;
  let measurementStarted = false;
  let openRequested = false;

  function beginMeasurement() {
    if (measurementStarted) return;
    measurementStarted = true;
    const row = rowRef.current;
    if (row === null || typeof row.measureInWindow !== 'function') {
      measuredFrame = null;
      if (openRequested) onOpen(null);
      return;
    }
    row.measureInWindow((x, y, width, height) => {
      measuredFrame = width > 0 && height > 0 ? { x, y, width, height } : null;
      if (openRequested) onOpen(measuredFrame);
    });
  }

  function handlePressIn(event: Parameters<NonNullable<PressableProps['onPressIn']>>[0]) {
    measuredFrame = undefined;
    measurementStarted = false;
    openRequested = false;
    beginMeasurement();
    onPressIn?.(event);
  }

  function handlePress() {
    if (measuredFrame !== undefined) {
      onOpen(measuredFrame);
      return;
    }
    openRequested = true;
    beginMeasurement();
  }

  return (
    <Pressable
      ref={rowRef}
      accessibilityRole="button"
      accessibilityLabel={`${title}. ${preview}`}
      accessibilityHint="Opens this conversation"
      onPressIn={handlePressIn}
      onPressOut={onPressOut}
      onPress={handlePress}
      className="-mx-3 flex-row items-start gap-4 rounded-2 px-3 py-3 active:bg-muted"
    >
      <View className="h-6 w-6 items-center justify-center">
        <Icon name="IconChatBubbles" size={24} color={colors.textSecondary} />
      </View>
      <View className="min-w-0 flex-1 gap-1">
        <Text className="text-foreground text-base-medium" numberOfLines={1}>
          {title}
        </Text>
        <Text className="text-muted-foreground text-small-regular" numberOfLines={1}>
          {preview}
        </Text>
        {needsAttention ? (
          <View className="flex-row items-center gap-1">
            <Icon name="IconCircleInfo" size={16} color={colors.warning} />
            <Text className="text-warning-600 text-small-regular">Needs attention</Text>
          </View>
        ) : null}
      </View>
    </Pressable>
  );
}

export function ChatListRow(props: ChatListRowProps) {
  const scale = useRef(new Animated.Value(1)).current;
  const openOnce = useRef(createOpenOnce(props.onOpen)).current;
  const [reduceMotion, setReduceMotion] = useState(false);

  useEffect(() => {
    let mounted = true;
    AccessibilityInfo.isReduceMotionEnabled().then((enabled) => {
      if (mounted) setReduceMotion(enabled);
    });
    const subscription = AccessibilityInfo.addEventListener('reduceMotionChanged', setReduceMotion);
    return () => {
      mounted = false;
      subscription.remove();
      scale.stopAnimation();
    };
  }, [scale]);

  function animateScale(toValue: number, duration: number) {
    scale.stopAnimation();
    if (reduceMotion) {
      scale.setValue(1);
      return;
    }
    Animated.timing(scale, {
      toValue,
      duration,
      easing: Easing.bezier(0.23, 1, 0.32, 1),
      useNativeDriver: true,
    }).start();
  }

  return (
    <Animated.View style={{ transform: [{ scale }] }}>
      <ChatListRowSurface
        {...props}
        onOpen={openOnce}
        onPressIn={() => animateScale(
          CHAT_LIST_ROW_MOTION.pressedScale,
          CHAT_LIST_ROW_MOTION.pressDuration,
        )}
        onPressOut={() => animateScale(1, CHAT_LIST_ROW_MOTION.releaseDuration)}
      />
    </Animated.View>
  );
}

import type { ReactNode } from 'react';
import {
  Pressable,
  View,
  type GestureResponderEvent,
  type StyleProp,
  type ViewStyle,
} from 'react-native';
import { useSharedValue, withSpring, withTiming } from 'react-native-reanimated';

import { LiquidGlassButtonSurface } from './LiquidGlassButtonSurface';
import type {
  LiquidGlassHierarchy,
  LiquidGlassShape,
  LiquidGlassTone,
} from './liquidGlass';

export interface LiquidGlassPressableProps {
  accessibilityLabel: string;
  hierarchy?: LiquidGlassHierarchy;
  tone?: LiquidGlassTone;
  shape?: LiquidGlassShape;
  disabled?: boolean;
  busy?: boolean;
  className?: string;
  style?: StyleProp<ViewStyle>;
  contentClassName?: string;
  children: ReactNode;
  hitSlop?: number;
  onPress: () => void;
  onPressIn?: (event: GestureResponderEvent) => void;
  onPressOut?: (event: GestureResponderEvent) => void;
}

export function getLiquidGlassPressableShape(
  shape: LiquidGlassShape = 'capsule',
): LiquidGlassShape {
  return shape;
}

export function LiquidGlassPressable({
  accessibilityLabel,
  hierarchy = 'standard',
  tone = 'neutral',
  shape = 'capsule',
  disabled = false,
  busy = false,
  className,
  style,
  contentClassName = 'flex-1 items-center justify-center',
  children,
  hitSlop,
  onPress,
  onPressIn,
  onPressOut,
}: LiquidGlassPressableProps) {
  const pressed = useSharedValue(0);

  function handlePressIn(event: GestureResponderEvent) {
    if (!disabled) pressed.value = withTiming(1, { duration: 100 });
    onPressIn?.(event);
  }

  function handlePressOut(event: GestureResponderEvent) {
    pressed.value = withSpring(0, { damping: 24, stiffness: 360 });
    onPressOut?.(event);
  }

  return (
    <Pressable
      accessibilityLabel={accessibilityLabel}
      accessibilityRole="button"
      accessibilityState={{ disabled, busy }}
      disabled={disabled}
      hitSlop={hitSlop}
      onPress={onPress}
      onPressIn={handlePressIn}
      onPressOut={handlePressOut}
      className={className}
      style={style}
    >
      <LiquidGlassButtonSurface
        hierarchy={hierarchy}
        tone={tone}
        shape={getLiquidGlassPressableShape(shape)}
        disabled={disabled}
        pressed={pressed}
        style={{ position: 'absolute', inset: 0 }}
      />
      <View pointerEvents="none" className={contentClassName}>
        {children}
      </View>
    </Pressable>
  );
}

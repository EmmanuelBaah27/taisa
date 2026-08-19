import { useEffect, useRef, useState } from 'react';
import {
  AccessibilityInfo,
  Animated,
  Easing,
  Pressable,
  type PressableProps,
} from 'react-native';

import { colors } from '../../constants/theme';
import { Icon, type IconName } from './Icon';

export const SECONDARY_ICON_BUTTON_FIGMA = {
  size: 56,
  iconSize: 24,
  padding: 16,
  borderRadius: 40,
  backgroundColor: colors.secondaryActionSurface,
  borderColor: colors.secondaryActionBorder,
  borderWidth: 1,
  shadowColor: colors.shadowSubtle,
  shadowOpacity: 0.04,
  shadowRadius: 6,
  elevation: 1,
} as const;

export const SECONDARY_ICON_BUTTON_MOTION = {
  pressedScale: 1.12,
  pressDuration: 70,
  holdDuration: 100,
  releaseDuration: 90,
} as const;

export interface SecondaryIconButtonProps {
  label: string;
  icon: IconName;
  disabled?: boolean;
  onPress: () => void;
}

interface SecondaryIconButtonSurfaceProps extends SecondaryIconButtonProps {
  onPressIn?: PressableProps['onPressIn'];
}

export function SecondaryIconButtonSurface({
  label,
  icon,
  disabled = false,
  onPress,
  onPressIn,
}: SecondaryIconButtonSurfaceProps) {
  const visual = SECONDARY_ICON_BUTTON_FIGMA;

  return (
    <Pressable
      accessibilityLabel={label}
      accessibilityRole="button"
      accessibilityState={{ disabled }}
      disabled={disabled}
      hitSlop={4}
      onPress={onPress}
      onPressIn={onPressIn}
      className="items-center justify-center rounded-full"
      style={{
        width: visual.size,
        height: visual.size,
        padding: visual.padding,
        borderRadius: visual.borderRadius,
        backgroundColor: visual.backgroundColor,
        borderColor: visual.borderColor,
        borderWidth: visual.borderWidth,
        shadowColor: visual.shadowColor,
        shadowOffset: { width: 0, height: 0 },
        shadowOpacity: visual.shadowOpacity,
        shadowRadius: visual.shadowRadius,
        elevation: visual.elevation,
        opacity: disabled ? 0.45 : 1,
      }}
    >
      <Icon name={icon} size={visual.iconSize} color={colors.secondaryActionIcon} />
    </Pressable>
  );
}

export function SecondaryIconButton(props: SecondaryIconButtonProps) {
  const scale = useRef(new Animated.Value(1)).current;
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

  const handlePressIn: NonNullable<PressableProps['onPressIn']> = () => {
    scale.stopAnimation();
    if (reduceMotion || props.disabled) {
      scale.setValue(1);
      return;
    }

    Animated.sequence([
      Animated.timing(scale, {
        toValue: SECONDARY_ICON_BUTTON_MOTION.pressedScale,
        duration: SECONDARY_ICON_BUTTON_MOTION.pressDuration,
        easing: Easing.out(Easing.cubic),
        useNativeDriver: true,
      }),
      Animated.delay(SECONDARY_ICON_BUTTON_MOTION.holdDuration),
      Animated.timing(scale, {
        toValue: 1,
        duration: SECONDARY_ICON_BUTTON_MOTION.releaseDuration,
        easing: Easing.bezier(0.77, 0, 0.175, 1),
        useNativeDriver: true,
      }),
    ]).start();
  };

  return (
    <Animated.View style={{ transform: [{ scale }] }}>
      <SecondaryIconButtonSurface {...props} onPressIn={handlePressIn} />
    </Animated.View>
  );
}

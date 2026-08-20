import {
  Pressable,
  type PressableProps,
} from 'react-native';
import { useSharedValue, withSpring, withTiming, type SharedValue } from 'react-native-reanimated';

import { colors } from '../../constants/theme';
import { Icon, type IconName } from './Icon';
import { LiquidGlassButtonSurface } from './LiquidGlassButtonSurface';

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
  pressedScale: 0.97,
  pressDuration: 100,
  releaseDamping: 24,
  releaseStiffness: 360,
} as const;

export interface SecondaryIconButtonProps {
  label: string;
  icon: IconName;
  disabled?: boolean;
  onPress: () => void;
}

interface SecondaryIconButtonSurfaceProps extends SecondaryIconButtonProps {
  onPressIn?: PressableProps['onPressIn'];
  onPressOut?: PressableProps['onPressOut'];
  pressed?: SharedValue<number>;
}

export function SecondaryIconButtonSurface({
  label,
  icon,
  disabled = false,
  onPress,
  onPressIn,
  onPressOut,
  pressed,
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
      onPressOut={onPressOut}
      className="items-center justify-center rounded-full"
      style={{
        width: visual.size,
        height: visual.size,
        padding: visual.padding,
        borderRadius: visual.borderRadius,
      }}
    >
      <LiquidGlassButtonSurface
        hierarchy="standard"
        tone="neutral"
        shape="circle"
        disabled={disabled}
        pressed={pressed}
        style={{ width: visual.size, height: visual.size, alignItems: 'center', justifyContent: 'center' }}
      >
        <Icon name={icon} size={visual.iconSize} color={colors.secondaryActionIcon} />
      </LiquidGlassButtonSurface>
    </Pressable>
  );
}

export function SecondaryIconButton(props: SecondaryIconButtonProps) {
  const pressed = useSharedValue(0);

  const handlePressIn: NonNullable<PressableProps['onPressIn']> = () => {
    if (!props.disabled) pressed.value = withTiming(1, { duration: SECONDARY_ICON_BUTTON_MOTION.pressDuration });
  };

  const handlePressOut: NonNullable<PressableProps['onPressOut']> = () => {
    pressed.value = withSpring(0, {
      damping: SECONDARY_ICON_BUTTON_MOTION.releaseDamping,
      stiffness: SECONDARY_ICON_BUTTON_MOTION.releaseStiffness,
    });
  };

  return <SecondaryIconButtonSurface {...props} pressed={pressed} onPressIn={handlePressIn} onPressOut={handlePressOut} />;
}

import React from 'react';
import { Pressable, Text, ActivityIndicator, View } from 'react-native';
import { useSharedValue, withSpring, withTiming } from 'react-native-reanimated';
import { colors } from '../../constants/theme';
import { LiquidGlassButtonSurface } from './LiquidGlassButtonSurface';
import type { LiquidGlassHierarchy, LiquidGlassTone } from './liquidGlass';

export type ButtonVariant =
  | 'primary'
  | 'secondary'
  | 'tertiary'
  | 'destructive'
  | 'secondary-destructive'
  | 'tertiary-destructive';

export type ButtonSize = 'default' | 'sm' | 'icon' | 'icon-lg';

export interface ButtonProps {
  /** Visual hierarchy level */
  variant?: ButtonVariant;
  size?: ButtonSize;
  /** Label text — used as accessible name for icon-only buttons */
  label: string;
  /** Optional icon node */
  icon?: React.ReactNode;
  /** Where to place the icon relative to label */
  iconPosition?: 'left' | 'right';
  /** Shows spinner and disables interaction */
  loading?: boolean;
  disabled?: boolean;
  onPress?: () => void;
}

const CONTAINER_BASE = 'rounded-full';

const VARIANT_CONTAINER_DISABLED: Record<ButtonVariant, string> = {
  'primary':               '',
  'secondary':             '',
  'tertiary':              '',
  'destructive':           '',
  'secondary-destructive': '',
  'tertiary-destructive':  '',
};

const VARIANT_TEXT: Record<ButtonVariant, string> = {
  'primary':               'text-primary-foreground',
  'secondary':             'text-foreground',
  'tertiary':              'text-foreground',
  'destructive':           'text-destructive-foreground',
  'secondary-destructive': 'text-danger',
  'tertiary-destructive':  'text-danger',
};

const SIZE_CONTAINER: Record<ButtonSize, string> = {
  default: 'h-[40px] px-5',
  sm:      'h-[32px] px-3',
  icon:    'h-[40px] w-[40px] p-[10px]',
  'icon-lg': 'h-[56px] w-[56px] p-4',
};

const SIZE_ICON_GAP: Record<ButtonSize, string> = {
  default: 'gap-2',
  sm:      'gap-1',
  icon:    '',
  'icon-lg': '',
};

const SIZE_TEXT: Record<ButtonSize, string> = {
  default: 'text-base font-semibold',
  sm:      'text-sm font-semibold',
  icon:    '',
  'icon-lg': '',
};

// Spinner color is the same as the text color for each variant
const SPINNER_COLOR: Record<ButtonVariant, string> = {
  'primary':               colors.textPrimary,        // dark text — lime bg is light
  'secondary':             colors.textPrimary,
  'tertiary':              colors.textPrimary,
  'destructive':           '#ffffff',
  'secondary-destructive': colors.error,
  'tertiary-destructive':  colors.error,
};

export function Button({
  variant = 'primary',
  size = 'default',
  label,
  icon,
  iconPosition = 'left',
  loading = false,
  disabled = false,
  onPress,
}: ButtonProps) {
  const pressed = useSharedValue(0);
  const isDisabled = disabled || loading;
  const isIconOnly = size === 'icon' || size === 'icon-lg';
  const hasIcon = !!icon && !isIconOnly && !loading;
  const iconSize = size === 'sm' ? 16 : size === 'icon-lg' ? 24 : 20;

  const containerClass = [
    CONTAINER_BASE,
    isDisabled ? VARIANT_CONTAINER_DISABLED[variant] : '',
    SIZE_CONTAINER[size],
    hasIcon ? SIZE_ICON_GAP[size] : '',
  ]
    .filter(Boolean)
    .join(' ');

  const textClass = [
    isDisabled ? 'text-disabled-foreground' : VARIANT_TEXT[variant],
    SIZE_TEXT[size],
  ]
    .filter(Boolean)
    .join(' ');
  const glass = getButtonLiquidGlassAppearance(variant);

  const content = loading ? (
    <ActivityIndicator
      size="small"
      color={isDisabled ? colors.textTertiary : SPINNER_COLOR[variant]}
    />
  ) : (
    <>
      {hasIcon && iconPosition === 'left' && (
        <View style={{ width: iconSize, height: iconSize, alignItems: 'center', justifyContent: 'center' }}>
          {icon}
        </View>
      )}
      {!isIconOnly && <Text className={textClass}>{label}</Text>}
      {hasIcon && iconPosition === 'right' && (
        <View style={{ width: iconSize, height: iconSize, alignItems: 'center', justifyContent: 'center' }}>
          {icon}
        </View>
      )}
      {isIconOnly && icon && (
        <View style={{ width: iconSize, height: iconSize, alignItems: 'center', justifyContent: 'center' }}>
          {icon}
        </View>
      )}
    </>
  );

  return (
    <Pressable
      className={containerClass}
      onPress={onPress}
      onPressIn={() => { pressed.value = withTiming(1, { duration: 100 }); }}
      onPressOut={() => { pressed.value = withSpring(0, { damping: 24, stiffness: 360 }); }}
      disabled={isDisabled}
      accessibilityLabel={label}
      accessibilityRole="button"
      accessibilityState={{ disabled: isDisabled, busy: loading }}
    >
      <LiquidGlassButtonSurface
        hierarchy={glass.hierarchy}
        tone={glass.tone}
        shape="capsule"
        disabled={isDisabled}
        pressed={pressed}
        style={{ position: 'absolute', inset: 0 }}
        testID="button-surface"
      />
      <View
        pointerEvents="none"
        className={['flex-1 flex-row items-center justify-center', hasIcon ? SIZE_ICON_GAP[size] : ''].join(' ')}
      >
        {content}
      </View>
    </Pressable>
  );
}

export function getButtonLiquidGlassAppearance(variant: ButtonVariant): {
  hierarchy: LiquidGlassHierarchy;
  tone: LiquidGlassTone;
} {
  if (variant === 'primary') return { hierarchy: 'prominent', tone: 'accent' };
  if (variant === 'destructive') return { hierarchy: 'prominent', tone: 'destructive' };
  if (variant === 'secondary') return { hierarchy: 'standard', tone: 'neutral' };
  if (variant === 'secondary-destructive') return { hierarchy: 'standard', tone: 'destructive' };
  if (variant === 'tertiary-destructive') return { hierarchy: 'subtle', tone: 'destructive' };
  return { hierarchy: 'subtle', tone: 'neutral' };
}

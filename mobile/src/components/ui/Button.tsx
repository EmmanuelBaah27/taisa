import React from 'react';
import { ActivityIndicator, View } from 'react-native';
import { colorTokens } from '../../design-system/tokens';
import { LiquidGlassPressable } from './LiquidGlassPressable';
import { Text } from './Text';
import type { TextColorRole } from './Text';
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

const VARIANT_TEXT: Record<ButtonVariant, TextColorRole> = {
  'primary':               'primary',
  'secondary':             'primary',
  'tertiary':              'primary',
  'destructive':           'inverted',
  'secondary-destructive': 'danger',
  'tertiary-destructive':  'danger',
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

const SIZE_TEXT: Record<ButtonSize, 'bodyStrong' | 'labelStrong'> = {
  default: 'bodyStrong',
  sm:      'labelStrong',
  icon:    'bodyStrong',
  'icon-lg': 'bodyStrong',
};

// Spinner color is the same as the text color for each variant
const SPINNER_COLOR: Record<ButtonVariant, string> = {
  'primary':               colorTokens.text.primary,
  'secondary':             colorTokens.text.primary,
  'tertiary':              colorTokens.text.primary,
  'destructive':           colorTokens.text.inverted,
  'secondary-destructive': colorTokens.status.danger,
  'tertiary-destructive':  colorTokens.status.danger,
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

  const glass = getButtonLiquidGlassAppearance(variant);

  const content = loading ? (
    <ActivityIndicator
      size="small"
      color={isDisabled ? colorTokens.text.disabled : SPINNER_COLOR[variant]}
    />
  ) : (
    <>
      {hasIcon && iconPosition === 'left' && (
        <View style={{ width: iconSize, height: iconSize, alignItems: 'center', justifyContent: 'center' }}>
          {icon}
        </View>
      )}
      {!isIconOnly && (
        <Text
          role={SIZE_TEXT[size]}
          color={isDisabled ? 'disabled' : VARIANT_TEXT[variant]}
        >
          {label}
        </Text>
      )}
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
    <LiquidGlassPressable
      accessibilityLabel={label}
      hierarchy={glass.hierarchy}
      tone={glass.tone}
      shape="capsule"
      className={containerClass}
      contentClassName={['flex-1 flex-row items-center justify-center', hasIcon ? SIZE_ICON_GAP[size] : ''].join(' ')}
      onPress={onPress ?? (() => undefined)}
      disabled={isDisabled}
      busy={loading}
    >
      {content}
    </LiquidGlassPressable>
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

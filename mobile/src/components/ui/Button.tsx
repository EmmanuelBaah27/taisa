import React from 'react';
import { Pressable, Text, ActivityIndicator, View } from 'react-native';

export type ButtonVariant =
  | 'primary'
  | 'secondary'
  | 'tertiary'
  | 'destructive'
  | 'secondary-destructive'
  | 'tertiary-destructive';

export type ButtonSize = 'default' | 'sm' | 'icon';

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

const CONTAINER_BASE = 'flex-row items-center justify-center rounded-full';

const VARIANT_CONTAINER: Record<ButtonVariant, string> = {
  'primary':               'bg-primary active:bg-primary-hover',
  'secondary':             'bg-card border border-border active:bg-subtle',
  'tertiary':              'bg-transparent active:bg-muted',
  'destructive':           'bg-destructive active:bg-destructive-hover',
  'secondary-destructive': 'bg-card border border-danger-border active:bg-danger-subtle',
  'tertiary-destructive':  'bg-transparent active:bg-danger-subtle',
};

const VARIANT_CONTAINER_DISABLED: Record<ButtonVariant, string> = {
  'primary':               'bg-disabled',
  'secondary':             'bg-card border border-border opacity-50',
  'tertiary':              'bg-transparent opacity-50',
  'destructive':           'bg-disabled',
  'secondary-destructive': 'bg-card border border-border opacity-50',
  'tertiary-destructive':  'bg-transparent opacity-50',
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
};

const SIZE_ICON_GAP: Record<ButtonSize, string> = {
  default: 'gap-2',
  sm:      'gap-1',
  icon:    '',
};

const SIZE_TEXT: Record<ButtonSize, string> = {
  default: 'text-base font-semibold',
  sm:      'text-sm font-semibold',
  icon:    '',
};

// Spinner color is the same as the text color for each variant
const SPINNER_COLOR: Record<ButtonVariant, string> = {
  'primary':               '#FFFFFF',
  'secondary':             '#0F0F0F',
  'tertiary':              '#0F0F0F',
  'destructive':           '#FFFFFF',
  'secondary-destructive': '#EF4444',
  'tertiary-destructive':  '#EF4444',
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
  const isIconOnly = size === 'icon';
  const hasIcon = !!icon && !isIconOnly && !loading;
  const iconSize = size === 'sm' ? 16 : 20;

  const containerClass = [
    CONTAINER_BASE,
    isDisabled ? VARIANT_CONTAINER_DISABLED[variant] : VARIANT_CONTAINER[variant],
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

  return (
    <Pressable
      className={containerClass}
      onPress={onPress}
      disabled={isDisabled}
      accessibilityLabel={label}
      accessibilityRole="button"
      accessibilityState={{ disabled: isDisabled, busy: loading }}
    >
      {loading ? (
        <ActivityIndicator
          size="small"
          color={isDisabled ? '#A3A3A3' : SPINNER_COLOR[variant]}
        />
      ) : (
        <>
          {hasIcon && iconPosition === 'left' && (
            <View style={{ width: iconSize, height: iconSize, alignItems: 'center', justifyContent: 'center' }}>
              {icon}
            </View>
          )}
          {!isIconOnly && (
            <Text className={textClass}>{label}</Text>
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
      )}
    </Pressable>
  );
}

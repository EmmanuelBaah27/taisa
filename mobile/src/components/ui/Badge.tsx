import React from 'react';
import { View, Text } from 'react-native';
import { LiquidGlassPressable } from './LiquidGlassPressable';

export type BadgeColor =
  | 'neutral'
  | 'yellow'
  | 'orange'
  | 'warning'
  | 'success'
  | 'info'
  | 'danger'
  | 'accent';

export type BadgeAppearance = 'subtle' | 'muted' | 'outline';
export type BadgeSize = 'default' | 'sm';

export interface BadgeProps {
  color?: BadgeColor;
  appearance?: BadgeAppearance;
  size?: BadgeSize;
  /** Leading icon node */
  icon?: React.ReactNode;
  /** Called when the dismiss × is pressed */
  onDismiss?: () => void;
  children: React.ReactNode;
}

type ColorStyle = { container: string; text: string };

const COLOR_STYLES: Record<BadgeColor, Record<BadgeAppearance, ColorStyle>> = {
  neutral: {
    subtle:  { container: 'bg-muted',                               text: 'text-muted-foreground' },
    muted:   { container: 'bg-disabled',                            text: 'text-muted-foreground' },
    outline: { container: 'bg-card border border-border-light',     text: 'text-muted-foreground' },
  },
  yellow: {
    subtle:  { container: 'bg-warning-subtle',                      text: 'text-warning-text' },
    muted:   { container: 'bg-warning-subtle',                      text: 'text-warning-text' },
    outline: { container: 'bg-card border border-border-light',     text: 'text-warning-text' },
  },
  orange: {
    subtle:  { container: 'bg-orange-subtle',                       text: 'text-orange-text' },
    muted:   { container: 'bg-orange-subtle',                       text: 'text-orange-text' },
    outline: { container: 'bg-card border border-border-light',     text: 'text-orange-text' },
  },
  warning: {
    subtle:  { container: 'bg-warning-subtle',                      text: 'text-warning-text' },
    muted:   { container: 'bg-warning-subtle',                      text: 'text-warning-text' },
    outline: { container: 'bg-card border border-border-light',     text: 'text-warning-text' },
  },
  success: {
    subtle:  { container: 'bg-success-subtle',                      text: 'text-success-text' },
    muted:   { container: 'bg-success-subtle',                      text: 'text-success-text' },
    outline: { container: 'bg-card border border-border-light',     text: 'text-success-text' },
  },
  info: {
    subtle:  { container: 'bg-info-subtle',                         text: 'text-info-text' },
    muted:   { container: 'bg-info-subtle',                         text: 'text-info-text' },
    outline: { container: 'bg-card border border-border-light',     text: 'text-info-text' },
  },
  danger: {
    subtle:  { container: 'bg-danger-subtle',                       text: 'text-danger-text' },
    muted:   { container: 'bg-danger-subtle',                       text: 'text-danger-text' },
    outline: { container: 'bg-card border border-danger-border',    text: 'text-danger-text' },
  },
  accent: {
    subtle:  { container: 'bg-accent-bg-light',                     text: 'text-accent-fg-light' },
    muted:   { container: 'bg-accent-bg-light',                     text: 'text-accent-fg-light' },
    outline: { container: 'bg-card border border-border-light',     text: 'text-accent-fg-light' },
  },
};

const SIZE_CONTAINER: Record<BadgeSize, string> = {
  default: 'py-0.5 px-2',
  sm:      'py-px px-1.5',
};

const SIZE_TEXT: Record<BadgeSize, string> = {
  default: 'text-xs font-normal leading-none',
  sm:      'text-xs font-normal leading-none tabular-nums',
};

export function Badge({
  color = 'neutral',
  appearance = 'subtle',
  size = 'default',
  icon,
  onDismiss,
  children,
}: BadgeProps) {
  const { container, text } = COLOR_STYLES[color][appearance];

  return (
    <View
      className={[
        'flex-row items-center justify-center gap-1 rounded-full self-start',
        container,
        SIZE_CONTAINER[size],
      ].join(' ')}
    >
      {icon && (
        <View className="items-center justify-center shrink-0">{icon}</View>
      )}

      <Text className={[text, SIZE_TEXT[size]].join(' ')}>
        {children}
      </Text>

      {onDismiss && (
        <LiquidGlassPressable
          onPress={onDismiss}
          hierarchy="subtle"
          shape="circle"
          className="ml-0.5 h-6 w-6"
          accessibilityLabel="Dismiss"
          hitSlop={8}
        >
          <Text className={[text, SIZE_TEXT[size]].join(' ')}>×</Text>
        </LiquidGlassPressable>
      )}
    </View>
  );
}

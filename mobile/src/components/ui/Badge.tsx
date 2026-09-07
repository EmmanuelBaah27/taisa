import React from 'react';
import { View } from 'react-native';
import { LiquidGlassPressable } from './LiquidGlassPressable';
import { Text } from './Text';
import type { TextColorRole } from './Text';

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

type ColorStyle = { container: string; text: TextColorRole };

const COLOR_STYLES: Record<BadgeColor, Record<BadgeAppearance, ColorStyle>> = {
  neutral: {
    subtle:  { container: 'bg-muted',                               text: 'secondary' },
    muted:   { container: 'bg-disabled',                            text: 'secondary' },
    outline: { container: 'bg-card border border-border-light',     text: 'secondary' },
  },
  yellow: {
    subtle:  { container: 'bg-warning-subtle',                      text: 'warning' },
    muted:   { container: 'bg-warning-subtle',                      text: 'warning' },
    outline: { container: 'bg-card border border-border-light',     text: 'warning' },
  },
  orange: {
    subtle:  { container: 'bg-orange-subtle',                       text: 'warning' },
    muted:   { container: 'bg-orange-subtle',                       text: 'warning' },
    outline: { container: 'bg-card border border-border-light',     text: 'warning' },
  },
  warning: {
    subtle:  { container: 'bg-warning-subtle',                      text: 'warning' },
    muted:   { container: 'bg-warning-subtle',                      text: 'warning' },
    outline: { container: 'bg-card border border-border-light',     text: 'warning' },
  },
  success: {
    subtle:  { container: 'bg-success-subtle',                      text: 'success' },
    muted:   { container: 'bg-success-subtle',                      text: 'success' },
    outline: { container: 'bg-card border border-border-light',     text: 'success' },
  },
  info: {
    subtle:  { container: 'bg-info-subtle',                         text: 'info' },
    muted:   { container: 'bg-info-subtle',                         text: 'info' },
    outline: { container: 'bg-card border border-border-light',     text: 'info' },
  },
  danger: {
    subtle:  { container: 'bg-danger-subtle',                       text: 'danger' },
    muted:   { container: 'bg-danger-subtle',                       text: 'danger' },
    outline: { container: 'bg-card border border-danger-border',    text: 'danger' },
  },
  accent: {
    subtle:  { container: 'bg-accent-bg-light',                     text: 'info' },
    muted:   { container: 'bg-accent-bg-light',                     text: 'info' },
    outline: { container: 'bg-card border border-border-light',     text: 'info' },
  },
};

const SIZE_CONTAINER: Record<BadgeSize, string> = {
  default: 'py-0.5 px-2',
  sm:      'py-px px-1.5',
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

      <Text role="metadataStrong" color={text}>
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
          <Text role="metadataStrong" color={text}>×</Text>
        </LiquidGlassPressable>
      )}
    </View>
  );
}

import React from 'react';
import { Text as NativeText } from 'react-native';
import type { TextProps as NativeTextProps } from 'react-native';

import type { TypographyRole } from '../../design-system/tokens';

export type TextColorRole =
  | 'primary'
  | 'secondary'
  | 'tertiary'
  | 'inverted'
  | 'disabled'
  | 'success'
  | 'warning'
  | 'danger'
  | 'info';

export const typographyRoleClasses: Record<TypographyRole, string> = {
  display: 'text-display',
  heading: 'text-heading',
  subheading: 'text-subheading',
  body: 'text-body',
  bodyStrong: 'text-bodyStrong',
  label: 'text-label',
  labelStrong: 'text-labelStrong',
  metadata: 'text-metadata',
  metadataStrong: 'text-metadataStrong',
};

export const textColorClasses: Record<TextColorRole, string> = {
  primary: 'text-foreground',
  secondary: 'text-muted-foreground',
  tertiary: 'text-text-tertiary',
  inverted: 'text-inverted-foreground',
  disabled: 'text-disabled-foreground',
  success: 'text-success-text',
  warning: 'text-warning-text',
  danger: 'text-danger-text',
  info: 'text-info-text',
};

export type TextAlignment = 'left' | 'center' | 'right';
export const textAlignmentClasses: Record<TextAlignment, string> = {
  left: 'text-left',
  center: 'text-center',
  right: 'text-right',
};

export interface TextProps extends Omit<NativeTextProps, 'style' | 'role'> {
  role?: TypographyRole;
  color?: TextColorRole;
  align?: TextAlignment;
  style?: never;
  className?: never;
}

export function Text({ role = 'body', color = 'primary', align, ...props }: TextProps) {
  return (
    <NativeText
      {...props}
      className={[typographyRoleClasses[role], textColorClasses[color], align ? textAlignmentClasses[align] : ''].filter(Boolean).join(' ')}
    />
  );
}

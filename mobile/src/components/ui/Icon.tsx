import type { FC } from 'react';
import type { SvgProps } from 'react-native-svg';
import * as CentralIcons from '@central-icons-react-native/round-outlined-radius-3-stroke-2';
import { colorTokens } from '../../design-system/tokens';

type AllExports = typeof CentralIcons;
export type IconName = Exclude<keyof AllExports, 'CentralIconBase' | `${string}Default`>;
export type IconColorRole = 'primary' | 'secondary' | 'tertiary' | 'inverted' | 'disabled' | 'success' | 'warning' | 'danger' | 'info';

export const iconColorValues: Record<IconColorRole, string> = {
  primary: colorTokens.text.primary,
  secondary: colorTokens.text.secondary,
  tertiary: colorTokens.text.tertiary,
  inverted: colorTokens.text.inverted,
  disabled: colorTokens.text.disabled,
  success: colorTokens.status.success,
  warning: colorTokens.status.warning,
  danger: colorTokens.status.danger,
  info: colorTokens.status.info,
};

export interface IconProps {
  name: IconName;
  size?: number;
  colorRole?: IconColorRole;
  /** @deprecated Product UI must use colorRole; retained during the current migration. */
  color?: string;
}

type IconComponent = FC<{ size?: number | string } & SvgProps>;

export function Icon({ name, size = 24, colorRole = 'primary', color }: IconProps) {
  const IconComponent = CentralIcons[name] as IconComponent | undefined;
  if (!IconComponent) return null;
  return <IconComponent size={size} color={color ?? iconColorValues[colorRole]} />;
}

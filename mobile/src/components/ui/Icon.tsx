import type { FC } from 'react';
import type { SvgProps } from 'react-native-svg';
import * as CentralIcons from '@central-icons-react-native/round-outlined-radius-3-stroke-2';

type AllExports = typeof CentralIcons;
export type IconName = Exclude<keyof AllExports, 'CentralIconBase' | `${string}Default`>;

export interface IconProps {
  name: IconName;
  size?: number;
  color?: string;
}

type IconComponent = FC<{ size?: number | string } & SvgProps>;

export function Icon({ name, size = 24, color = 'currentColor' }: IconProps) {
  const IconComponent = CentralIcons[name] as IconComponent | undefined;
  if (!IconComponent) return null;
  return <IconComponent size={size} color={color} />;
}

import { SvgXml } from 'react-native-svg';
import { iconPaths } from './icon-paths';

export type IconName = keyof typeof iconPaths;

export interface IconProps {
  name: IconName;
  size?: number;
  color?: string;
}

export function Icon({ name, size = 20, color = 'currentColor' }: IconProps) {
  const content = iconPaths[name];
  if (!content) return null;

  const xml = `<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">${content}</svg>`;
  return <SvgXml xml={xml} width={size} height={size} color={color} />;
}

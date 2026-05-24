import { createAvatar } from '@usenavii/core';
import { SvgXml } from 'react-native-svg';

interface NaviiAvatarProps {
  seed: string;
  size: number;
}

export function NaviiAvatar({ seed, size }: NaviiAvatarProps) {
  const svg = createAvatar(seed, { size });
  return <SvgXml xml={svg} width={size} height={size} />;
}

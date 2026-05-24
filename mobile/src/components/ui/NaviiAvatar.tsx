import { selectAvatar, renderAvatar } from '@usenavii/core';
import { SvgXml } from 'react-native-svg';

interface NaviiAvatarProps {
  seed: string;
  size: number;
}

export function NaviiAvatar({ seed, size }: NaviiAvatarProps) {
  const spec = selectAvatar(seed);
  const svg = renderAvatar({ ...spec, body: 'pear', background: 'none' }, { size, paletteId: 'sky' });
  return <SvgXml xml={svg} width={size} height={size} />;
}

import { selectAvatar, renderAvatar } from '@usenavii/core';
import { SvgXml } from 'react-native-svg';

interface NaviiAvatarProps {
  seed: string;
  size: number;
}

export function NaviiAvatar({ seed, size }: NaviiAvatarProps) {
  const spec = selectAvatar(seed, { paletteId: 'sky', background: 'none' });
  const svg = renderAvatar({ ...spec, body: 'pear', accessory: 'eyepatch', topper: 'none', hueShift: 0 }, { size });
  return <SvgXml xml={svg} width={size} height={size} />;
}

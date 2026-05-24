import { selectAvatar, renderAvatar } from '@usenavii/core';
import { SvgXml } from 'react-native-svg';

const SKY = { id: 'sky', bodyFrom: '#93C5FD', bodyTo: '#3B82F6', accent: '#FFFFFF', ink: '#1E3A8A', blush: '#F9A8D4' };

interface NaviiAvatarProps {
  seed: string;
  size: number;
}

export function NaviiAvatar({ seed, size }: NaviiAvatarProps) {
  const spec = selectAvatar(seed);
  const svg = renderAvatar({ ...spec, body: 'pear', background: 'none', palette: SKY }, { size });
  return <SvgXml xml={svg} width={size} height={size} />;
}

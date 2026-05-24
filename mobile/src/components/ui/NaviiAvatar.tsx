import { createAvatar } from '@usenavii/core';
import { View } from 'react-native';
import { SvgXml } from 'react-native-svg';

interface NaviiAvatarProps {
  seed: string;
  size: number;
}

export function NaviiAvatar({ seed, size }: NaviiAvatarProps) {
  const inner = size - 4;
  const svg = createAvatar(seed, { size: inner, background: 'none' });
  return (
    <View style={{ width: size, height: size, padding: 2 }}>
      <SvgXml xml={svg} width={inner} height={inner} />
    </View>
  );
}

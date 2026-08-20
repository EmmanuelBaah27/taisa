import { BlurView } from 'expo-blur';
import { LinearGradient } from 'expo-linear-gradient';
import type { ReactNode } from 'react';
import { View } from 'react-native';

import { colors } from '../../constants/theme';

export type PageHeaderVariant = 'title' | 'workspace';

export interface PageHeaderSurfaceProps {
  children: ReactNode;
  variant: PageHeaderVariant;
}

export function getPageHeaderScrollInset(
  paddingTop: number,
  variant: PageHeaderVariant,
): number {
  return variant === 'workspace' ? paddingTop + 66 : paddingTop + 44;
}

export function PageHeaderSurface({ children, variant: _variant }: PageHeaderSurfaceProps) {
  return (
    <View
      pointerEvents="box-none"
      style={{ position: 'absolute', top: 0, left: 0, right: 0, zIndex: 20 }}
    >
      <BlurView
        pointerEvents="none"
        intensity={42}
        tint="systemThinMaterialLight"
        style={{ position: 'absolute', inset: 0 }}
      />
      <View
        pointerEvents="none"
        style={{ position: 'absolute', inset: 0, backgroundColor: colors.pageHeaderTint }}
      />
      {children}
      <LinearGradient
        pointerEvents="none"
        colors={[colors.pageHeaderFade, colors.backgroundTransparent]}
        locations={[0, 1]}
        style={{ position: 'absolute', left: 0, right: 0, bottom: -24, height: 24 }}
      />
    </View>
  );
}

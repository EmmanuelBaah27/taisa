import type { ReactNode } from 'react';
import { Pressable } from 'react-native';

import { BOTTOM_NAVIGATION_FIGMA } from '../../navigation/bottomNavigation';
import { Icon, type IconName } from './Icon';

export interface InactiveNavigationItemProps {
  accessibilityLabel: string;
  icon: IconName;
  leadingVisual?: ReactNode;
  onPress: () => void;
  onPressIn?: () => void;
  onPressOut?: () => void;
}

const INACTIVE = BOTTOM_NAVIGATION_FIGMA.inactiveItem;

export function InactiveNavigationItem({
  accessibilityLabel,
  icon,
  leadingVisual,
  onPress,
  onPressIn,
  onPressOut,
}: InactiveNavigationItemProps) {
  return (
    <Pressable
      accessibilityLabel={accessibilityLabel}
      accessibilityRole="tab"
      accessibilityState={{ selected: false }}
      hitSlop={4}
      onPress={onPress}
      onPressIn={onPressIn}
      onPressOut={onPressOut}
      style={{
        width: INACTIVE.width,
        height: INACTIVE.height,
        alignItems: 'center',
        justifyContent: 'center',
        paddingHorizontal: INACTIVE.paddingHorizontal,
        paddingVertical: INACTIVE.paddingVertical,
      }}
    >
      {leadingVisual ?? (
        <Icon name={icon} size={INACTIVE.iconSize} color={INACTIVE.iconColor} />
      )}
    </Pressable>
  );
}

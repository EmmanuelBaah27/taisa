import type { ReactNode } from 'react';
import { Pressable, Text, View } from 'react-native';

import {
  BOTTOM_NAVIGATION_ACTIVE_FILL,
  BOTTOM_NAVIGATION_FIGMA,
} from '../../navigation/bottomNavigation';

export interface SelectedNavigationItemProps {
  label: string;
  leadingVisual: ReactNode;
  width: number;
  onPress: () => void;
  onPressIn?: () => void;
  onPressOut?: () => void;
}

const SELECTED = BOTTOM_NAVIGATION_FIGMA.selectedItem;

export function SelectedNavigationItem({
  label,
  leadingVisual,
  width,
  onPress,
  onPressIn,
  onPressOut,
}: SelectedNavigationItemProps) {
  return (
    <Pressable
      accessibilityLabel={label}
      accessibilityRole="tab"
      accessibilityState={{ selected: true }}
      hitSlop={4}
      onPress={onPress}
      onPressIn={onPressIn}
      onPressOut={onPressOut}
      style={{
        width,
        height: SELECTED.height,
        alignItems: 'center',
        justifyContent: 'center',
        paddingHorizontal: SELECTED.paddingHorizontal,
        paddingVertical: SELECTED.paddingVertical,
        borderRadius: SELECTED.borderRadius,
        backgroundColor: BOTTOM_NAVIGATION_ACTIVE_FILL,
      }}
    >
      <View
        style={{
          flexDirection: 'row',
          alignItems: 'center',
          gap: SELECTED.gap,
        }}
      >
        {leadingVisual}
        <Text
          numberOfLines={1}
          className="font-sans-medium text-[#0F1010]"
          style={{
            fontSize: SELECTED.fontSize,
            lineHeight: SELECTED.lineHeight,
            letterSpacing: SELECTED.letterSpacing,
          }}
        >
          {label}
        </Text>
      </View>
    </Pressable>
  );
}

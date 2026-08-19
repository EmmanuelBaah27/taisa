import type { ReactNode } from 'react';
import { Animated, View } from 'react-native';
import type { StyleProp, TextStyle, ViewStyle } from 'react-native';

import {
  BOTTOM_NAVIGATION_ACTIVE_FILL,
  BOTTOM_NAVIGATION_FIGMA,
  type NavigationCapsuleFrame,
  type NavigationCapsulePhase,
} from '../../navigation/bottomNavigation';

export interface PersistentNavigationCapsuleProps {
  label: 'Home' | 'Chats' | 'Me';
  leadingVisual: ReactNode;
  frame: NavigationCapsuleFrame;
  phase: NavigationCapsulePhase;
  animatedContainerStyle?: StyleProp<ViewStyle>;
  animatedLabelStyle?: StyleProp<TextStyle>;
}

const SELECTED = BOTTOM_NAVIGATION_FIGMA.selectedItem;

export function PersistentNavigationCapsule({
  label,
  leadingVisual,
  frame,
  phase,
  animatedContainerStyle,
  animatedLabelStyle,
}: PersistentNavigationCapsuleProps) {
  const backgroundColor =
    phase === 'resting' ? BOTTOM_NAVIGATION_ACTIVE_FILL : 'transparent';

  return (
    <Animated.View
      accessible={false}
      pointerEvents="none"
      style={[
        {
          position: 'absolute',
          top: (BOTTOM_NAVIGATION_FIGMA.navigationHeight - SELECTED.height) / 2,
        },
        {
          left: frame.x,
          width: frame.width,
        },
        {
          height: SELECTED.height,
          alignItems: 'center',
          justifyContent: 'center',
          paddingHorizontal: SELECTED.paddingHorizontal,
          paddingVertical: SELECTED.paddingVertical,
          borderRadius: SELECTED.borderRadius,
        },
        { backgroundColor },
        animatedContainerStyle,
      ]}
    >
      <View
        style={{
          flexDirection: 'row',
          alignItems: 'center',
          gap: SELECTED.gap,
        }}
      >
        {leadingVisual}
        <Animated.Text
          numberOfLines={1}
          className="font-sans-medium text-foreground"
          style={[
            {
              fontSize: SELECTED.fontSize,
              lineHeight: SELECTED.lineHeight,
              letterSpacing: SELECTED.letterSpacing,
            },
            animatedLabelStyle,
          ]}
        >
          {label}
        </Animated.Text>
      </View>
    </Animated.View>
  );
}

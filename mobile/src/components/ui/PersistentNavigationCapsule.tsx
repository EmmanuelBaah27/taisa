import type { ReactNode } from 'react';
import { Animated } from 'react-native';
import type { StyleProp, TextStyle, ViewStyle } from 'react-native';

import {
  BOTTOM_NAVIGATION_ACTIVE_FILL,
  BOTTOM_NAVIGATION_CLEAR_GLASS_SURFACE,
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
  animatedContentStyle?: StyleProp<ViewStyle>;
  animatedFillStyle?: StyleProp<ViewStyle>;
  animatedLabelStyle?: StyleProp<TextStyle>;
  outgoingLabel?: 'Home' | 'Chats' | 'Me';
  animatedOutgoingLabelStyle?: StyleProp<TextStyle>;
}

const SELECTED = BOTTOM_NAVIGATION_FIGMA.selectedItem;

export function PersistentNavigationCapsule({
  label,
  leadingVisual,
  frame,
  phase,
  animatedContainerStyle,
  animatedContentStyle,
  animatedFillStyle,
  animatedLabelStyle,
  outgoingLabel,
  animatedOutgoingLabelStyle,
}: PersistentNavigationCapsuleProps) {
  const travellingSurfaceStyle = phase === 'resting'
    ? undefined
    : BOTTOM_NAVIGATION_CLEAR_GLASS_SURFACE;

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
          overflow: 'hidden',
        },
        travellingSurfaceStyle,
        animatedContainerStyle,
      ]}
    >
      <Animated.View
        pointerEvents="none"
        style={[
          {
            position: 'absolute',
            inset: 0,
            backgroundColor: BOTTOM_NAVIGATION_ACTIVE_FILL,
          },
          { opacity: phase === 'resting' ? 1 : 0 },
          animatedFillStyle,
        ]}
      />
      <Animated.View
        style={[
          {
            flexDirection: 'row',
            alignItems: 'center',
            gap: SELECTED.gap,
          },
          animatedContentStyle,
        ]}
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
      </Animated.View>
      {outgoingLabel ? (
        <Animated.Text
          numberOfLines={1}
          className="absolute font-sans-medium text-foreground"
          style={[
            {
              top: SELECTED.paddingVertical,
              left: SELECTED.paddingHorizontal + SELECTED.iconSize + SELECTED.gap,
              fontSize: SELECTED.fontSize,
              lineHeight: SELECTED.lineHeight,
              letterSpacing: SELECTED.letterSpacing,
            },
            animatedOutgoingLabelStyle,
          ]}
        >
          {outgoingLabel}
        </Animated.Text>
      ) : null}
    </Animated.View>
  );
}

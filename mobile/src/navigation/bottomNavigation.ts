import type { IconName } from '../components/ui/Icon';

export interface BottomNavigationItem {
  id: 'index' | 'logs' | 'you';
  label: 'Home' | 'Chats' | 'Me';
  path: '/' | '/logs' | '/you';
  icon: IconName;
}

export const BOTTOM_NAVIGATION_ITEMS: readonly BottomNavigationItem[] = [
  { id: 'index', label: 'Home', path: '/', icon: 'IconHomeLine' },
  { id: 'logs', label: 'Chats', path: '/logs', icon: 'IconChatBubbles' },
  { id: 'you', label: 'Me', path: '/you', icon: 'IconPeopleCircle' },
];

export const BOTTOM_NAVIGATION_ACTIVE_FILL = 'rgba(15,16,16,0.06)';

export const BOTTOM_NAVIGATION_FIGMA = {
  navigationHeight: 60,
  navigationBottom: 36,
  referenceSafeAreaBottom: 34,
  recordGap: 12,
  fadeBottom: 20,
  fadeHeight: 90,
  selectedItem: {
    height: 48,
    iconSize: 24,
    gap: 8,
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderRadius: 32,
    fontSize: 16,
    lineHeight: 24,
    letterSpacing: -0.36,
  },
  inactiveItem: {
    width: 56,
    height: 48,
    iconSize: 24,
    paddingHorizontal: 16,
    paddingVertical: 12,
    iconColor: '#9C9C9C',
  },
  pressMotion: {
    pressedScaleX: 1.05,
    pressedScaleY: 0.9,
    pressInDuration: 100,
    releaseDuration: 300,
    releaseBounce: 0.25,
  },
  shellMotion: {
    pressedScaleX: 1.025,
    pressedScaleY: 0.96,
    pressDelay: 20,
    pressInDuration: 110,
    releaseDuration: 340,
    releaseBounce: 0.2,
  },
} as const;

export function getBottomNavigationStateLayout(activeId: BottomNavigationItem['id']) {
  if (activeId === 'index') {
    return {
      navigationWidth: 240,
      itemWidths: [108, 56, 56] as const,
      activeContentDirection: 'row' as const,
    };
  }
  if (activeId === 'logs') {
    return {
      navigationWidth: 240,
      itemWidths: [56, 108, 56] as const,
      activeContentDirection: 'row' as const,
    };
  }
  return {
    navigationWidth: 220,
    itemWidths: [56, 56, 88] as const,
    activeContentDirection: 'row' as const,
  };
}

export function getBottomNavigationLayout(safeAreaBottom: number) {
  const safeAreaAdjustment = Math.max(
    0,
    safeAreaBottom - BOTTOM_NAVIGATION_FIGMA.referenceSafeAreaBottom,
  );
  const navigationBottom = BOTTOM_NAVIGATION_FIGMA.navigationBottom + safeAreaAdjustment;

  return {
    navigationBottom,
    navigationHeight: BOTTOM_NAVIGATION_FIGMA.navigationHeight,
    recordBottom:
      navigationBottom
      + BOTTOM_NAVIGATION_FIGMA.navigationHeight
      + BOTTOM_NAVIGATION_FIGMA.recordGap,
    fadeBottom: BOTTOM_NAVIGATION_FIGMA.fadeBottom + safeAreaAdjustment,
    fadeHeight: BOTTOM_NAVIGATION_FIGMA.fadeHeight,
  };
}

export function resolveGlassAvailability(
  isAPIAvailable: () => boolean,
  isLiquidGlassAvailable: () => boolean,
): boolean {
  try {
    return isAPIAvailable() && isLiquidGlassAvailable();
  } catch {
    return false;
  }
}

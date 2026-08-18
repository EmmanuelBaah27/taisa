import type { IconName } from '../components/ui/Icon';

export interface BottomNavigationItem {
  id: 'index' | 'logs' | 'you';
  label: 'Home' | 'Chats' | 'Account';
  path: '/' | '/logs' | '/you';
  icon: IconName;
}

export const BOTTOM_NAVIGATION_ITEMS: readonly BottomNavigationItem[] = [
  { id: 'index', label: 'Home', path: '/', icon: 'IconHomeLine' },
  { id: 'logs', label: 'Chats', path: '/logs', icon: 'IconChatBubbles' },
  { id: 'you', label: 'Account', path: '/you', icon: 'IconPeopleCircle' },
];

export const BOTTOM_NAVIGATION_FIGMA = {
  navigationHeight: 60,
  navigationBottom: 36,
  referenceSafeAreaBottom: 34,
  recordGap: 12,
  fadeBottom: 20,
  fadeHeight: 90,
} as const;

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

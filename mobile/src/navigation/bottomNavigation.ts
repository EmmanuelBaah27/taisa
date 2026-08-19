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

export interface NavigationCapsuleFrame {
  shellWidth: number;
  x: number;
  width: number;
}

export type NavigationCapsulePhase = 'resting' | 'travelling' | 'settling';

export interface NavigationCapsuleState {
  from: BottomNavigationItem['id'];
  to: BottomNavigationItem['id'];
  phase: NavigationCapsulePhase;
}

export const BOTTOM_NAVIGATION_CAPSULE_FRAMES: Record<
  BottomNavigationItem['id'],
  NavigationCapsuleFrame
> = {
  index: { shellWidth: 240, x: 6, width: 108 },
  logs: { shellWidth: 240, x: 66, width: 108 },
  you: { shellWidth: 220, x: 126, width: 88 },
};

export function getBottomNavigationCapsuleFrame(
  id: BottomNavigationItem['id'],
): NavigationCapsuleFrame {
  return BOTTOM_NAVIGATION_CAPSULE_FRAMES[id];
}

export function getBottomNavigationCapsuleCenterOffset(
  id: BottomNavigationItem['id'],
): number {
  const frame = getBottomNavigationCapsuleFrame(id);
  return frame.x - (frame.shellWidth / 2);
}

export function startBottomNavigationTransition(
  state: NavigationCapsuleState,
  destination: BottomNavigationItem['id'],
): NavigationCapsuleState {
  if (destination === state.to) return state;

  return {
    from: state.to,
    to: destination,
    phase: 'travelling',
  };
}

export function settleBottomNavigationTransition(
  state: NavigationCapsuleState,
): NavigationCapsuleState {
  return { from: state.to, to: state.to, phase: 'resting' };
}

export function shouldShowBottomNavigationSelectedFill(
  state: NavigationCapsuleState,
): boolean {
  return state.phase === 'resting';
}

export function shouldReleaseBottomNavigationCancelledPress(
  navigationCommitted: boolean,
  state: NavigationCapsuleState,
): boolean {
  return !navigationCommitted && state.phase === 'resting';
}

export function getBottomNavigationRenderPolicy(
  state: NavigationCapsuleState,
) {
  return {
    selectedContentLayers: 1 as const,
    hiddenStableDestination: state.to,
  };
}

export function getBottomNavigationTransitionStartPolicy() {
  return {
    beforeRoute: true as const,
    deferred: false as const,
  };
}

export const BOTTOM_NAVIGATION_ACTIVE_FILL = 'rgba(15,16,16,0.06)';
export const BOTTOM_NAVIGATION_CLEAR_GLASS_SURFACE = {
  backgroundColor: 'rgba(255,255,255,0.12)',
  borderColor: 'rgba(255,255,255,0.34)',
  borderWidth: 1,
} as const;

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
  shellMotion: {
    pressedScale: 1.12,
    pressDuration: 90,
    releaseDuration: 320,
    releaseDampingRatio: 0.78,
  },
  capsuleMotion: {
    duration: 280,
    dampingRatio: 0.82,
  },
  labelMotion: {
    enterScale: 0.94,
    enterTranslateX: -6,
    duration: 180,
  },
  reducedMotion: {
    crossfadeDuration: 180,
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

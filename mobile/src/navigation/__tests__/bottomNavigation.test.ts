import {
  BOTTOM_NAVIGATION_ITEMS,
  BOTTOM_NAVIGATION_ACTIVE_FILL,
  BOTTOM_NAVIGATION_FIGMA,
  BOTTOM_NAVIGATION_FALLBACK_GLASS,
  commitBottomNavigationRoute,
  getBottomNavigationCapsuleFrame,
  getBottomNavigationCapsuleCenterOffset,
  getBottomNavigationDestinationCenterOffset,
  getBottomNavigationDestinationOffsets,
  getBottomNavigationInteractiveCapsuleFrames,
  getBottomNavigationRenderPolicy,
  getBottomNavigationPageTransition,
  getBottomNavigationSurfaceTimeline,
  getBottomNavigationTransitionStartPolicy,
  getBottomNavigationLayout,
  getBottomNavigationItemFrames,
  getAdjacentBottomNavigationDestination,
  getBottomNavigationStateLayout,
  resolveGlassAvailability,
  resolveOptionalGlassModule,
  resolveCapsuleInteractiveIndex,
  settleBottomNavigationTransition,
  shouldReleaseBottomNavigationCancelledPress,
  shouldShowBottomNavigationSelectedFill,
  startBottomNavigationTransition,
} from '../bottomNavigation';
import { navigateWithMainNavigation } from '../MainNavigationInteractionContext';

describe('bottom navigation', () => {
  test('uses one isolated UI-thread style for interactive capsule tracking', () => {
    const source = readFileSync(
      resolve(__dirname, '../../components/ui/BottomNavBar.tsx'),
      'utf8',
    );

    expect(source.match(/useAnimatedStyle/g)).toHaveLength(2);
    expect(source).toContain("from 'react-native-reanimated'");
    expect(source).toContain('interactiveCapsuleStyle');
    expect(source).not.toContain('destinationLabelWidths');
    expect(source).not.toContain('destinationIconTranslations');
  });

  test('exposes only the approved Home, Chats, and Me destinations', () => {
    expect(BOTTOM_NAVIGATION_ITEMS).toEqual([
      { id: 'chats', label: 'Chats', path: '/chats', icon: 'IconChatBubbles' },
      { id: 'index', label: 'Home', path: '/', icon: 'IconHomeLine' },
      { id: 'you', label: 'Me', path: '/you', icon: 'IconPeopleCircle' },
    ]);
  });

  test('pages horizontally through Chats, Home, and Me without wrapping', () => {
    expect(getAdjacentBottomNavigationDestination('index', 'right')).toBe('chats');
    expect(getAdjacentBottomNavigationDestination('index', 'left')).toBe('you');
    expect(getAdjacentBottomNavigationDestination('chats', 'right')).toBeNull();
    expect(getAdjacentBottomNavigationDestination('you', 'left')).toBeNull();
  });

  test('matches the Figma bottom-control geometry on the reference device', () => {
    expect(getBottomNavigationLayout(34)).toEqual({
      navigationBottom: 36,
      navigationHeight: 60,
      recordBottom: 108,
      fadeBottom: 20,
      fadeHeight: 90,
    });
  });

  test('preserves the Figma spacing above larger safe areas', () => {
    expect(getBottomNavigationLayout(44)).toEqual({
      navigationBottom: 46,
      navigationHeight: 60,
      recordBottom: 118,
      fadeBottom: 30,
      fadeHeight: 90,
    });
  });

  test('falls back safely when a linked glass module is unavailable at runtime', () => {
    const missingNativeModule = () => {
      throw new Error("Cannot find native module 'ExpoGlassEffect'");
    };

    expect(resolveGlassAvailability(missingNativeModule, () => true)).toBe(false);
  });

  test('does not crash the app shell when the optional glass module fails to load', () => {
    const missingNativeModule = () => {
      throw new Error("Cannot find native module 'ExpoGlassEffect'");
    };

    expect(resolveOptionalGlassModule(true, missingNativeModule)).toBeNull();
  });

  test('does not evaluate the optional native glass module until explicitly enabled', () => {
    const loader = jest.fn(() => ({ GlassView: 'native' }));

    expect(resolveOptionalGlassModule(false, loader)).toBeNull();
    expect(loader).not.toHaveBeenCalled();

    expect(resolveOptionalGlassModule(true, loader)).toEqual({ GlassView: 'native' });
    expect(loader).toHaveBeenCalledTimes(1);
  });

  test('matches the Figma width for each active navigation state', () => {
    expect(getBottomNavigationStateLayout('index')).toEqual({
      navigationWidth: 240,
      itemWidths: [56, 108, 56],
      activeContentDirection: 'row',
    });
    expect(getBottomNavigationStateLayout('chats')).toEqual({
      navigationWidth: 240,
      itemWidths: [108, 56, 56],
      activeContentDirection: 'row',
    });
    expect(getBottomNavigationStateLayout('you')).toEqual({
      navigationWidth: 220,
      itemWidths: [56, 56, 88],
      activeContentDirection: 'row',
    });
  });

  test('uses the approved six-percent black active fill', () => {
    expect(BOTTOM_NAVIGATION_ACTIVE_FILL).toBe('rgba(15,16,16,0.06)');
  });

  test('keeps the blur fallback visibly glassy on white screens', () => {
    expect(BOTTOM_NAVIGATION_FALLBACK_GLASS).toEqual({
      intensity: 70,
      tint: 'systemThinMaterialLight',
      borderColor: 'rgba(15,16,16,0.10)',
      sheenColors: ['rgba(255,255,255,0.42)', 'rgba(255,255,255,0.06)'],
    });
  });

  test('matches the Figma selected-item geometry', () => {
    expect(BOTTOM_NAVIGATION_FIGMA.selectedItem).toEqual({
      height: 48,
      iconSize: 24,
      gap: 8,
      paddingHorizontal: 16,
      paddingVertical: 12,
      borderRadius: 32,
      fontSize: 16,
      lineHeight: 24,
      letterSpacing: -0.36,
    });
  });

  test('matches the Figma inactive-item geometry and color', () => {
    expect(BOTTOM_NAVIGATION_FIGMA.inactiveItem).toEqual({
      width: 56,
      height: 48,
      iconSize: 24,
      paddingHorizontal: 16,
      paddingVertical: 12,
      iconColor: '#9C9C9C',
    });
  });

  test('scales the entire glass shell uniformly until the capsule settles', () => {
    expect(BOTTOM_NAVIGATION_FIGMA.shellMotion).toEqual({
      pressedScale: 1.12,
      pressDuration: 70,
      holdDuration: 100,
      releaseDuration: 90,
      releaseDampingRatio: 0.78,
      releaseCompletesWithTravel: true,
      scalesContent: false,
    });
  });

  test('does not compound the shell scale with a second capsule scale', () => {
    expect(BOTTOM_NAVIGATION_FIGMA.capsuleMotion).toEqual({
      duration: 260,
      easing: [0.22, 1, 0.36, 1],
      coordinatesShellWidth: true,
      coordinatesTabIcons: true,
      directIconTrajectory: true,
      travellingScale: 1,
      expandedHeight: 48,
    });
  });

  test('keeps destination hit targets fixed while the capsule moves', () => {
    expect(getBottomNavigationDestinationCenterOffset('chats')).toBe(-60);
    expect(getBottomNavigationDestinationCenterOffset('index')).toBe(0);
    expect(getBottomNavigationDestinationCenterOffset('you')).toBe(60);
  });

  test('moves inactive destinations clear of the selected capsule', () => {
    expect(getBottomNavigationDestinationOffsets('chats')).toEqual([-60, 26, 86]);
    expect(getBottomNavigationDestinationOffsets('index')).toEqual([-86, 0, 86]);
    expect(getBottomNavigationDestinationOffsets('you')).toEqual([-76, -16, 60]);
  });

  test('keeps each tab identity in a persistent destination frame', () => {
    expect(getBottomNavigationItemFrames('index')).toEqual([
      { x: 6, width: 56 }, { x: 66, width: 108 }, { x: 178, width: 56 },
    ]);
    expect(getBottomNavigationItemFrames('chats')).toEqual([
      { x: 6, width: 108 }, { x: 118, width: 56 }, { x: 178, width: 56 },
    ]);
    expect(getBottomNavigationItemFrames('you')).toEqual([
      { x: 6, width: 56 }, { x: 66, width: 56 }, { x: 126, width: 88 },
    ]);
  });

  test('moves the selected label outward from its destination icon', () => {
    expect(BOTTOM_NAVIGATION_FIGMA.labelMotion).toEqual({
      enterScale: 0.84,
      enterTranslateX: -8,
      duration: 160,
      exitDuration: 80,
      exitMotion: 'fade-in-place',
      transformOrigin: 'left center',
      reveal: 'opacity-scale',
    });
  });

  test('routes immediately and fades the destination while the capsule is still travelling', () => {
    const events: string[] = [];
    commitBottomNavigationRoute(() => events.push('route'));
    events.push('after-commit');

    expect(events).toEqual(['route', 'after-commit']);
    expect(getBottomNavigationPageTransition()).toEqual({
      sceneAnimation: 'fade',
      backdropColor: '#ffffff',
    });
    expect(BOTTOM_NAVIGATION_FIGMA.capsuleMotion.duration).toBe(260);
  });

  test('crossfades reduced-motion surfaces and content together', () => {
    expect(BOTTOM_NAVIGATION_FIGMA.reducedMotion).toEqual({
      crossfadeDuration: 180,
    });
  });

  test('matches the persistent capsule frame for each destination', () => {
    expect(getBottomNavigationCapsuleFrame('chats')).toEqual({ shellWidth: 240, x: 6, width: 108 });
    expect(getBottomNavigationCapsuleFrame('index')).toEqual({ shellWidth: 240, x: 66, width: 108 });
    expect(getBottomNavigationCapsuleFrame('you')).toEqual({ shellWidth: 220, x: 126, width: 88 });
  });

  test('keeps capsule coordinates stable when the centered shell changes width', () => {
    expect(getBottomNavigationCapsuleCenterOffset('chats')).toBe(-114);
    expect(getBottomNavigationCapsuleCenterOffset('index')).toBe(-54);
    expect(getBottomNavigationCapsuleCenterOffset('you')).toBe(16);
  });

  test('derives interactive capsule frames from the destination registry geometry', () => {
    expect(getBottomNavigationInteractiveCapsuleFrames()).toEqual([
      { id: 'chats', width: 108, centerOffset: -114 },
      { id: 'index', width: 108, centerOffset: -54 },
      { id: 'you', width: 88, centerOffset: 16 },
    ]);
  });

  test('derives capsule selection from interactive swipe progress without committing early', () => {
    expect(resolveCapsuleInteractiveIndex({ fromIndex: 1, toIndex: 2, progress: 0.49 })).toBe(1);
    expect(resolveCapsuleInteractiveIndex({ fromIndex: 1, toIndex: 2, progress: 0.51 })).toBe(2);
    expect(resolveCapsuleInteractiveIndex({ fromIndex: 1, toIndex: null, progress: 0 })).toBe(1);
  });

  test('prefers the custom navigator and uses the Expo router only as an outside fallback', () => {
    const navigate = jest.fn();
    const fallback = jest.fn();

    navigateWithMainNavigation({ navigate }, 'you', fallback);

    expect(navigate).toHaveBeenCalledWith('you');
    expect(fallback).not.toHaveBeenCalled();

    navigateWithMainNavigation(null, 'chats', fallback);

    expect(fallback).toHaveBeenCalledTimes(1);
  });

  test('uses a faint neutral elevation instead of a lime navigation glow', () => {
    expect(BOTTOM_NAVIGATION_FIGMA.elevation).toEqual({
      color: '#5B5F63',
      opacity: 0.12,
      radius: 24,
      offsetY: 8,
      elevation: 8,
    });
  });

  test('models travelling, interruption, settlement, and selected fill visibility', () => {
    const resting = { from: 'chats', to: 'chats', phase: 'resting' } as const;
    const travelling = startBottomNavigationTransition(resting, 'you');

    expect(travelling).toEqual({ from: 'chats', to: 'you', phase: 'travelling' });
    expect(shouldShowBottomNavigationSelectedFill(travelling)).toBe(false);
    expect(startBottomNavigationTransition(travelling, 'index')).toEqual({
      from: 'you',
      to: 'index',
      phase: 'travelling',
    });
    expect(settleBottomNavigationTransition(travelling)).toEqual({
      from: 'you',
      to: 'you',
      phase: 'resting',
    });
    expect(shouldShowBottomNavigationSelectedFill(resting)).toBe(true);
  });

  test('releases a cancelled press only when no transition was committed', () => {
    const resting = { from: 'chats', to: 'chats', phase: 'resting' } as const;
    const travelling = { from: 'chats', to: 'you', phase: 'travelling' } as const;

    expect(shouldReleaseBottomNavigationCancelledPress(false, resting)).toBe(true);
    expect(shouldReleaseBottomNavigationCancelledPress(true, resting)).toBe(false);
    expect(shouldReleaseBottomNavigationCancelledPress(false, travelling)).toBe(false);
  });

  test('keeps all tab identities persistent above a content-free selected surface', () => {
    const resting = { from: 'chats', to: 'chats', phase: 'resting' } as const;
    const travelling = { from: 'chats', to: 'you', phase: 'travelling' } as const;

    expect(getBottomNavigationRenderPolicy(resting)).toEqual({
      persistentTabContentLayers: 3,
      selectedSurfaceContentLayers: 0,
      hiddenTabIcons: 0,
      labelsOwnTheirTabIdentity: true,
    });
    expect(getBottomNavigationRenderPolicy(travelling)).toEqual({
      persistentTabContentLayers: 3,
      selectedSurfaceContentLayers: 0,
      hiddenTabIcons: 0,
      labelsOwnTheirTabIdentity: true,
    });
  });

  test('coordinates shell width, capsule travel, and fill restoration on one settlement', () => {
    expect(BOTTOM_NAVIGATION_FIGMA.capsuleMotion.coordinatesShellWidth).toBe(true);
    expect(getBottomNavigationSurfaceTimeline(false)).toEqual({
      spatialMotion: true,
      fillFadeOutDuration: 90,
      fillRestoreDelay: 120,
      fillRestoreDuration: 180,
      restoreCompletesWithSettlement: true,
    });
    expect(getBottomNavigationSurfaceTimeline(true)).toEqual({
      spatialMotion: false,
      crossfadeDuration: 180,
      labelOnlyOverlap: true,
    });
  });

  test('starts capsule motion synchronously before routing', () => {
    expect(getBottomNavigationTransitionStartPolicy()).toEqual({
      startEvent: 'pressIn',
      beforeRoute: true,
      deferred: false,
      routeEvent: 'press',
      cancelReturnsToOrigin: true,
    });
  });

});
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

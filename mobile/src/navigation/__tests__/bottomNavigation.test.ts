import {
  BOTTOM_NAVIGATION_ITEMS,
  BOTTOM_NAVIGATION_ACTIVE_FILL,
  BOTTOM_NAVIGATION_FIGMA,
  BOTTOM_NAVIGATION_FALLBACK_GLASS,
  getBottomNavigationCapsuleFrame,
  getBottomNavigationCapsuleCenterOffset,
  getBottomNavigationDestinationCenterOffset,
  getBottomNavigationDestinationOffsets,
  getBottomNavigationRenderPolicy,
  getBottomNavigationSurfaceTimeline,
  getBottomNavigationTransitionStartPolicy,
  getBottomNavigationLayout,
  getBottomNavigationItemFrames,
  getBottomNavigationStateLayout,
  resolveGlassAvailability,
  resolveOptionalGlassModule,
  settleBottomNavigationTransition,
  shouldReleaseBottomNavigationCancelledPress,
  shouldShowBottomNavigationSelectedFill,
  startBottomNavigationTransition,
} from '../bottomNavigation';

describe('bottom navigation', () => {
  test('does not mount Reanimated hooks that crash under iOS Fabric', () => {
    const source = readFileSync(
      resolve(__dirname, '../../components/ui/BottomNavBar.tsx'),
      'utf8',
    );

    expect(source).not.toMatch(/useAnimatedStyle|useSharedValue/);
    expect(source).not.toContain("from 'react-native-reanimated'");
    expect(source).not.toContain('destinationLabelWidths');
    expect(source).not.toContain('destinationIconTranslations');
  });

  test('exposes only the approved Home, Chats, and Me destinations', () => {
    expect(BOTTOM_NAVIGATION_ITEMS).toEqual([
      { id: 'index', label: 'Home', path: '/', icon: 'IconHomeLine' },
      { id: 'logs', label: 'Chats', path: '/logs', icon: 'IconChatBubbles' },
      { id: 'you', label: 'Me', path: '/you', icon: 'IconPeopleCircle' },
    ]);
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
      itemWidths: [108, 56, 56],
      activeContentDirection: 'row',
    });
    expect(getBottomNavigationStateLayout('logs')).toEqual({
      navigationWidth: 240,
      itemWidths: [56, 108, 56],
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
    expect(getBottomNavigationDestinationCenterOffset('index')).toBe(-60);
    expect(getBottomNavigationDestinationCenterOffset('logs')).toBe(0);
    expect(getBottomNavigationDestinationCenterOffset('you')).toBe(60);
  });

  test('moves inactive destinations clear of the selected capsule', () => {
    expect(getBottomNavigationDestinationOffsets('index')).toEqual([-60, 26, 86]);
    expect(getBottomNavigationDestinationOffsets('logs')).toEqual([-86, 0, 86]);
    expect(getBottomNavigationDestinationOffsets('you')).toEqual([-76, -16, 60]);
  });

  test('keeps each tab identity in a persistent destination frame', () => {
    expect(getBottomNavigationItemFrames('index')).toEqual([
      { x: 6, width: 108 }, { x: 118, width: 56 }, { x: 178, width: 56 },
    ]);
    expect(getBottomNavigationItemFrames('logs')).toEqual([
      { x: 6, width: 56 }, { x: 66, width: 108 }, { x: 178, width: 56 },
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

  test('lets navigation motion establish before mounting the destination screen', () => {
    expect(BOTTOM_NAVIGATION_FIGMA.routeMotionLeadDuration).toBe(260);
  });

  test('crossfades reduced-motion surfaces and content together', () => {
    expect(BOTTOM_NAVIGATION_FIGMA.reducedMotion).toEqual({
      crossfadeDuration: 180,
    });
  });

  test('matches the persistent capsule frame for each destination', () => {
    expect(getBottomNavigationCapsuleFrame('index')).toEqual({ shellWidth: 240, x: 6, width: 108 });
    expect(getBottomNavigationCapsuleFrame('logs')).toEqual({ shellWidth: 240, x: 66, width: 108 });
    expect(getBottomNavigationCapsuleFrame('you')).toEqual({ shellWidth: 220, x: 126, width: 88 });
  });

  test('keeps capsule coordinates stable when the centered shell changes width', () => {
    expect(getBottomNavigationCapsuleCenterOffset('index')).toBe(-114);
    expect(getBottomNavigationCapsuleCenterOffset('logs')).toBe(-54);
    expect(getBottomNavigationCapsuleCenterOffset('you')).toBe(16);
  });

  test('models travelling, interruption, settlement, and selected fill visibility', () => {
    const resting = { from: 'logs', to: 'logs', phase: 'resting' } as const;
    const travelling = startBottomNavigationTransition(resting, 'you');

    expect(travelling).toEqual({ from: 'logs', to: 'you', phase: 'travelling' });
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
    const resting = { from: 'logs', to: 'logs', phase: 'resting' } as const;
    const travelling = { from: 'logs', to: 'you', phase: 'travelling' } as const;

    expect(shouldReleaseBottomNavigationCancelledPress(false, resting)).toBe(true);
    expect(shouldReleaseBottomNavigationCancelledPress(true, resting)).toBe(false);
    expect(shouldReleaseBottomNavigationCancelledPress(false, travelling)).toBe(false);
  });

  test('keeps all tab identities persistent above a content-free selected surface', () => {
    const resting = { from: 'logs', to: 'logs', phase: 'resting' } as const;
    const travelling = { from: 'logs', to: 'you', phase: 'travelling' } as const;

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

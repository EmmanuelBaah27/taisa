import {
  BOTTOM_NAVIGATION_ITEMS,
  BOTTOM_NAVIGATION_ACTIVE_FILL,
  BOTTOM_NAVIGATION_FIGMA,
  getBottomNavigationCapsuleFrame,
  getBottomNavigationLayout,
  getBottomNavigationStateLayout,
  resolveGlassAvailability,
  settleBottomNavigationTransition,
  shouldShowBottomNavigationSelectedFill,
  startBottomNavigationTransition,
} from '../bottomNavigation';

describe('bottom navigation', () => {
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

  test('uses a perceptible jelly deformation for tab presses', () => {
    expect(BOTTOM_NAVIGATION_FIGMA.pressMotion).toEqual({
      pressedScaleX: 1.05,
      pressedScaleY: 0.9,
      pressInDuration: 100,
      releaseDuration: 300,
      releaseBounce: 0.25,
    });
  });

  test('propagates a gentler jelly deformation through the glass shell', () => {
    expect(BOTTOM_NAVIGATION_FIGMA.shellMotion).toEqual({
      pressedScaleX: 1.025,
      pressedScaleY: 0.96,
      pressDelay: 20,
      pressInDuration: 110,
      releaseDuration: 340,
      releaseBounce: 0.2,
    });
  });

  test('matches the persistent capsule frame for each destination', () => {
    expect(getBottomNavigationCapsuleFrame('index')).toEqual({ shellWidth: 240, x: 6, width: 108 });
    expect(getBottomNavigationCapsuleFrame('logs')).toEqual({ shellWidth: 240, x: 66, width: 108 });
    expect(getBottomNavigationCapsuleFrame('you')).toEqual({ shellWidth: 220, x: 126, width: 88 });
  });

  test('models travelling, interruption, settlement, and selected fill visibility', () => {
    const resting = { from: 'logs', to: 'logs', phase: 'resting' } as const;
    const travelling = startBottomNavigationTransition(resting, 'you');

    expect(travelling).toEqual({ from: 'logs', to: 'you', phase: 'travelling' });
    expect(shouldShowBottomNavigationSelectedFill(travelling)).toBe(false);
    expect(startBottomNavigationTransition(travelling, 'index')).toEqual({
      from: 'logs',
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

});

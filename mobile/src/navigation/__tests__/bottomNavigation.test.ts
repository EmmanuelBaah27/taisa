import {
  BOTTOM_NAVIGATION_ITEMS,
  getBottomNavigationLayout,
  resolveGlassAvailability,
} from '../bottomNavigation';

describe('bottom navigation', () => {
  test('exposes only the approved Home, Chats, and Account destinations', () => {
    expect(BOTTOM_NAVIGATION_ITEMS).toEqual([
      { id: 'index', label: 'Home', path: '/', icon: 'IconHomeLine' },
      { id: 'logs', label: 'Chats', path: '/logs', icon: 'IconChatBubbles' },
      { id: 'you', label: 'Account', path: '/you', icon: 'IconPeopleCircle' },
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
});

import {
  getInteractiveSceneWindow,
  MAIN_EDGE_RESISTANCE,
  MAIN_SWIPE_DISTANCE,
  MAIN_SWIPE_TRACKING,
  MAIN_SWIPE_VELOCITY,
  resolveMainSwipe,
} from '../interactiveMainNavigation';

describe('interactive main navigation policy', () => {
  test('keeps the active scene and the adjacent scene in the swipe direction', () => {
    expect(getInteractiveSceneWindow(['chats', 'index', 'you'], 1, -1)).toEqual([0, 1]);
    expect(getInteractiveSceneWindow(['chats', 'index', 'you'], 1, 1)).toEqual([1, 2]);
    expect(getInteractiveSceneWindow(['chats', 'index', 'you'], 1, 0)).toEqual([1]);
  });

  test('commits a leftward swipe when translation passes the distance threshold', () => {
    expect(resolveMainSwipe({
      activeIndex: 1,
      routeCount: 3,
      translationX: -80,
      velocityX: -200,
    })).toEqual({ kind: 'commit', destinationIndex: 2, direction: 1 });
  });

  test('cancels a rightward swipe at the first route edge', () => {
    expect(resolveMainSwipe({
      activeIndex: 0,
      routeCount: 3,
      translationX: 160,
      velocityX: 1200,
    })).toEqual({ kind: 'cancel', edge: true });
  });

  test('publishes the approved gesture policy constants', () => {
    expect(MAIN_SWIPE_TRACKING).toBe(0.98);
    expect(MAIN_SWIPE_DISTANCE).toBe(72);
    expect(MAIN_SWIPE_VELOCITY).toBe(700);
    expect(MAIN_EDGE_RESISTANCE).toBe(0.18);
  });

  test('cancels a gesture that does not cross either commit threshold', () => {
    expect(resolveMainSwipe({
      activeIndex: 1,
      routeCount: 3,
      translationX: 40,
      velocityX: 300,
    })).toEqual({ kind: 'cancel', edge: false });
  });

  test('commits when velocity crosses the threshold in the gesture direction', () => {
    expect(resolveMainSwipe({
      activeIndex: 1,
      routeCount: 3,
      translationX: 12,
      velocityX: 701,
    })).toEqual({ kind: 'commit', destinationIndex: 0, direction: -1 });
  });

  test('does not commit an opposing velocity as if it were the gesture direction', () => {
    expect(resolveMainSwipe({
      activeIndex: 1,
      routeCount: 3,
      translationX: 12,
      velocityX: -701,
    })).toEqual({ kind: 'cancel', edge: false });
  });

  test('keeps scene-window indices unique, sorted, and in range', () => {
    expect(getInteractiveSceneWindow(['chats', 'index'], 0, -1)).toEqual([0]);
    expect(getInteractiveSceneWindow(['chats', 'index'], 1, 1)).toEqual([1]);
    expect(getInteractiveSceneWindow([], 0, 1)).toEqual([]);
  });
});

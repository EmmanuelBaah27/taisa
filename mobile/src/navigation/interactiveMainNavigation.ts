export type MainDestinationId = 'chats' | 'index' | 'you';

export const MAIN_SWIPE_TRACKING = 0.98;
export const MAIN_SWIPE_DISTANCE = 72;
export const MAIN_SWIPE_VELOCITY = 700;
export const MAIN_EDGE_RESISTANCE = 0.18;

export type MainNavigationInterruption = 'background' | 'dimension-change' | 'route-replace';

export function getInteractiveMotionMode(reduceMotion: boolean): 'fade' | 'spatial' {
  return reduceMotion ? 'fade' : 'spatial';
}

export function resolveInterruption(_reason: MainNavigationInterruption) {
  return { cancelGesture: true, normalizeTrack: true } as const;
}

export interface MainSwipeInput {
  activeIndex: number;
  routeCount: number;
  translationX: number;
  velocityX: number;
}

export type MainSwipeResolution =
  | { kind: 'commit'; destinationIndex: number; direction: -1 | 1 }
  | { kind: 'cancel'; edge: boolean };

export function getInteractiveSceneWindow(
  routeNames: readonly string[],
  activeIndex: number,
  direction: -1 | 0 | 1,
): readonly number[] {
  if (routeNames.length === 0) return [];

  const normalizedActiveIndex = Number.isFinite(activeIndex)
    ? Math.trunc(activeIndex)
    : 0;
  const safeActiveIndex = Math.min(
    routeNames.length - 1,
    Math.max(0, normalizedActiveIndex),
  );

  if (direction === 0) return [safeActiveIndex];

  const adjacentIndex = safeActiveIndex + direction;
  if (adjacentIndex < 0 || adjacentIndex >= routeNames.length) {
    return [safeActiveIndex];
  }

  return direction === -1
    ? [adjacentIndex, safeActiveIndex]
    : [safeActiveIndex, adjacentIndex];
}

export function getMainSceneFrames(
  routeNames: readonly string[],
  activeIndex: number,
  direction: -1 | 0 | 1,
  viewportWidth: number,
): readonly { index: number; left: number }[] {
  return getInteractiveSceneWindow(routeNames, activeIndex, direction).map((index) => ({
    index,
    left: (index - activeIndex) * viewportWidth,
  }));
}

export function resolveMainSwipe({
  activeIndex,
  routeCount,
  translationX,
  velocityX,
}: MainSwipeInput): MainSwipeResolution {
  const translationDirection: -1 | 0 | 1 = translationX < 0
    ? 1
    : translationX > 0
      ? -1
      : 0;
  const velocityDirection: -1 | 0 | 1 = velocityX < 0
    ? 1
    : velocityX > 0
      ? -1
      : 0;
  const direction = translationDirection || velocityDirection;

  if (direction === 0) return { kind: 'cancel', edge: false };

  const destinationIndex = activeIndex + direction;
  const destinationIsOutOfRange =
    !Number.isInteger(activeIndex) ||
    routeCount <= 0 ||
    activeIndex < 0 ||
    activeIndex >= routeCount ||
    destinationIndex < 0 ||
    destinationIndex >= routeCount;

  if (destinationIsOutOfRange) return { kind: 'cancel', edge: true };

  const distanceExceeded = Math.abs(translationX) > MAIN_SWIPE_DISTANCE;
  const velocityExceeded =
    velocityDirection === direction &&
    Math.abs(velocityX) > MAIN_SWIPE_VELOCITY;

  if (!distanceExceeded && !velocityExceeded) {
    return { kind: 'cancel', edge: false };
  }

  return { kind: 'commit', destinationIndex, direction };
}

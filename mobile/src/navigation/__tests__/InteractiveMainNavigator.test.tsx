import fs from 'node:fs';
import path from 'node:path';
import React from 'react';
import { StyleSheet, View } from 'react-native';
import { cancelAnimation, withSpring, withTiming } from 'react-native-reanimated';

jest.mock('react-native', () => {
  const actual = jest.requireActual<typeof import('react-native')>('react-native');
  let viewportWidth = 390;
  let reduceMotion = false;
  let appStateListener: ((state: string) => void) | null = null;

  const mocked = Object.create(actual);
  Object.defineProperties(mocked, {
    AccessibilityInfo: { value: {
      ...actual.AccessibilityInfo,
      addEventListener: jest.fn(() => ({ remove: jest.fn() })),
      announceForAccessibility: jest.fn(),
      isReduceMotionEnabled: jest.fn(async () => reduceMotion),
      setAccessibilityFocus: jest.fn(),
    } },
    AppState: { value: {
      ...actual.AppState,
      addEventListener: jest.fn((_event: string, listener: (state: string) => void) => {
        appStateListener = listener;
        return { remove: jest.fn(() => { appStateListener = null; }) };
      }),
    } },
    findNodeHandle: { value: jest.fn((node: unknown) => (node ? 101 : null)) },
    useWindowDimensions: { value: () => ({
      width: viewportWidth,
      height: 844,
      scale: 3,
      fontScale: 1,
    }) },
    __emitAppState: { value: (state: string) => appStateListener?.(state) },
    __setReduceMotion: { value: (enabled: boolean) => { reduceMotion = enabled; } },
    __setViewportWidth: { value: (width: number) => { viewportWidth = width; } },
  });
  return mocked;
});

jest.mock('react-native-gesture-handler', () => {
  let latestHandlers: Record<string, ((...args: any[]) => void) | undefined> = {};
  let latestConfig: Record<string, unknown> = {};

  return {
    GestureDetector: ({ children }: { children: React.ReactNode }) => children,
    Gesture: {
      Pan: jest.fn(() => {
        latestHandlers = {};
        latestConfig = {};
        const gesture = {
          enabled(value: unknown) {
            latestConfig.enabled = value;
            return gesture;
          },
          activeOffsetX(value: unknown) {
            latestConfig.activeOffsetX = value;
            return gesture;
          },
          failOffsetY(value: unknown) {
            latestConfig.failOffsetY = value;
            return gesture;
          },
          cancelsTouchesInView(value: unknown) {
            latestConfig.cancelsTouchesInView = value;
            return gesture;
          },
          onBegin(callback: (...args: any[]) => void) {
            latestHandlers.onBegin = callback;
            return gesture;
          },
          onUpdate(callback: (...args: any[]) => void) {
            latestHandlers.onUpdate = callback;
            return gesture;
          },
          onEnd(callback: (...args: any[]) => void) {
            latestHandlers.onEnd = callback;
            return gesture;
          },
          onFinalize(callback: (...args: any[]) => void) {
            latestHandlers.onFinalize = callback;
            return gesture;
          },
        };
        return gesture;
      }),
    },
    __getLatestPanConfig: () => latestConfig,
    __getLatestPanHandlers: () => latestHandlers,
  };
});

jest.mock('react-native-reanimated', () => {
  const ReactModule = jest.requireActual<typeof import('react')>('react');
  const ReactNative = jest.requireMock<typeof import('react-native')>('react-native');

  return {
    __esModule: true,
    default: { View: ReactNative.View },
    cancelAnimation: jest.fn(),
    interpolate: (
      value: number,
      input: readonly [number, number],
      output: readonly [number, number],
    ) => output[0] + ((value - input[0]) / (input[1] - input[0])) * (output[1] - output[0]),
    runOnJS: (callback: (...args: any[]) => unknown) => callback,
    useAnimatedStyle: (factory: () => object) => factory(),
    useSharedValue: <T,>(initialValue: T) =>
      ReactModule.useRef({ value: initialValue }).current,
    withSpring: jest.fn((toValue: number, _config?: object, callback?: (finished: boolean) => void) => {
      callback?.(true);
      return toValue;
    }),
    withTiming: jest.fn((toValue: number) => toValue),
  };
});

jest.mock('../../components/VoiceButton', () => ({ VoiceButton: () => null }));
jest.mock('../../components/ui/BottomNavBar', () => ({ BottomNavBar: () => null }));

import {
  InteractiveMainNavigatorView,
  type InteractiveMainNavigatorViewProps,
} from '../InteractiveMainNavigator';
import {
  type MainNavigationInteractionValue,
  useMainNavigationInteraction,
} from '../MainNavigationInteractionContext';

type TestInstance = {
  props: Record<string, any>;
  findByProps(props: Record<string, unknown>): TestInstance;
  findAllByProps(props: Record<string, unknown>): TestInstance[];
};
type TestRenderer = {
  root: TestInstance;
  update(element: React.ReactElement): void;
  unmount(): void;
};

const ReactTestRenderer = jest.requireActual('react-test-renderer') as {
  act(callback: () => void | Promise<void>): void | Promise<void>;
  create(element: React.ReactElement): TestRenderer;
};
const { act, create } = ReactTestRenderer;
const mockCancelAnimation = cancelAnimation as jest.MockedFunction<typeof cancelAnimation>;
const mockWithSpring = withSpring as jest.MockedFunction<typeof withSpring>;
const mockWithTiming = withTiming as jest.MockedFunction<typeof withTiming>;

const nativeHarness = jest.requireMock('react-native') as {
  AccessibilityInfo: {
    announceForAccessibility: jest.Mock;
    setAccessibilityFocus: jest.Mock;
  };
  __emitAppState(state: string): void;
  __setReduceMotion(enabled: boolean): void;
  __setViewportWidth(width: number): void;
};
const gestureHarness = jest.requireMock('react-native-gesture-handler') as {
  __getLatestPanConfig(): Record<string, unknown>;
  __getLatestPanHandlers(): {
    onBegin?: () => void;
    onUpdate?: (event: { translationX: number; velocityX: number }) => void;
    onEnd?: (event: { translationX: number; velocityX: number }) => void;
    onFinalize?: (event: object, success: boolean) => void;
  };
};

const mountedRenderers: TestRenderer[] = [];
let capturedInteraction: MainNavigationInteractionValue | null = null;
let consoleErrorSpy: jest.SpyInstance;

function CapturingBottomNavigation() {
  capturedInteraction = useMainNavigationInteraction();
  return <View testID="capturing-bottom-navigation" />;
}

function buildRouteKeys(routeNames: readonly string[]) {
  return routeNames.map((name, index) => `${name}-key-${index}`);
}

async function renderNavigator({
  index = 1,
  routeNames = ['chats', 'index', 'you'],
  routeKeys = buildRouteKeys(routeNames),
  reduceMotion = false,
}: {
  index?: number;
  routeNames?: readonly string[];
  routeKeys?: readonly string[];
  reduceMotion?: boolean;
} = {}) {
  nativeHarness.__setReduceMotion(reduceMotion);
  const navigation = { dispatch: jest.fn() };
  const mountMocks = Object.fromEntries(
    routeNames.map((name) => [name, jest.fn()]),
  ) as Record<string, jest.Mock>;
  const unmountMocks = Object.fromEntries(
    routeNames.map((name) => [name, jest.fn()]),
  ) as Record<string, jest.Mock>;
  function DescriptorProbe({ routeName }: { routeName: string }) {
    React.useEffect(() => {
      mountMocks[routeName]();
      return () => unmountMocks[routeName]();
    }, [routeName]);

    return <View accessibilityLabel={`${routeName} descriptor`} />;
  }
  const renderMocks = Object.fromEntries(
    routeNames.map((name) => [
      name,
      jest.fn(() => <DescriptorProbe routeName={name} />),
    ]),
  ) as Record<string, jest.Mock>;
  let renderer!: TestRenderer;

  const element = (
    nextIndex: number,
    nextRouteNames = routeNames,
    nextRouteKeys = routeKeys,
  ) => {
    const routes = nextRouteNames.map((name, routeIndex) => ({
      key: nextRouteKeys[routeIndex],
      name,
    }));
    const descriptors = Object.fromEntries(
      routes.map((route) => [
        route.key,
        { render: renderMocks[route.name] },
      ]),
    );

    return (
      <InteractiveMainNavigatorView
        state={{
          stale: false,
          type: 'tab',
          key: 'main-tabs',
          index: nextIndex,
          routeNames: [...nextRouteNames],
          history: [{ type: 'route', key: routes[nextIndex].key }],
          preloadedRouteKeys: [],
          routes,
        }}
        navigation={navigation as unknown as InteractiveMainNavigatorViewProps['navigation']}
        descriptors={descriptors as unknown as InteractiveMainNavigatorViewProps['descriptors']}
        BottomNavBar={CapturingBottomNavigation}
        VoiceButton={() => null}
      />
    );
  };

  await act(async () => {
    renderer = create(element(index));
    await Promise.resolve();
  });
  mountedRenderers.push(renderer);

  return {
    navigation,
    mountMocks,
    renderMocks,
    renderer,
    unmountMocks,
    async rerender(
      nextIndex: number,
      nextRouteNames = routeNames,
      nextRouteKeys = routeKeys,
    ) {
      await act(async () => {
        renderer.update(element(nextIndex, nextRouteNames, nextRouteKeys));
        await Promise.resolve();
      });
    },
  };
}

function queryByTestId(renderer: TestRenderer, testID: string) {
  return renderer.root.findAllByProps({ testID })[0] ?? null;
}

function getByTestId(renderer: TestRenderer, testID: string) {
  return renderer.root.findByProps({ testID });
}

function flattenedStyle(renderer: TestRenderer, testID: string) {
  return StyleSheet.flatten(getByTestId(renderer, testID).props.style);
}

async function drag(translationX: number, velocityX = 0) {
  await act(async () => {
    gestureHarness.__getLatestPanHandlers().onUpdate?.({ translationX, velocityX });
    await Promise.resolve();
  });
}

function timingCallbackFor(target: number, duration: number) {
  const call = mockWithTiming.mock.calls.findLast(
    ([toValue, config]) => toValue === target && config?.duration === duration,
  );
  return call?.[2];
}

describe('InteractiveMainNavigator', () => {
  beforeAll(() => {
    (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
    const originalConsoleError = console.error.bind(console);
    consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation((...args: unknown[]) => {
      if (args[0] === 'react-test-renderer is deprecated. See https://react.dev/warnings/react-test-renderer') {
        return;
      }
      originalConsoleError(...args);
    });
  });

  afterAll(() => {
    consoleErrorSpy.mockRestore();
  });

  beforeEach(() => {
    jest.clearAllMocks();
    capturedInteraction = null;
    nativeHarness.__setReduceMotion(false);
    nativeHarness.__setViewportWidth(390);
  });

  afterEach(() => {
    for (const renderer of mountedRenderers.splice(0)) {
      act(() => renderer.unmount());
    }
  });

  test('renders only the active descriptor at rest', async () => {
    const { renderMocks, renderer } = await renderNavigator();

    expect(getByTestId(renderer, 'main-scene-index')).toBeTruthy();
    expect(queryByTestId(renderer, 'main-scene-chats')).toBeNull();
    expect(queryByTestId(renderer, 'main-scene-you')).toBeNull();
    expect(renderMocks.index).toHaveBeenCalledTimes(1);
    expect(renderMocks.chats).not.toHaveBeenCalled();
    expect(renderMocks.you).not.toHaveBeenCalled();
  });

  test('renders only the active and directional adjacent descriptors during left and right drags', async () => {
    const left = await renderNavigator();
    Object.values(left.renderMocks).forEach((mock) => mock.mockClear());

    expect(gestureHarness.__getLatestPanConfig()).toMatchObject({
      activeOffsetX: [-18, 18],
      failOffsetY: [-14, 14],
      cancelsTouchesInView: true,
    });
    expect(
      (gestureHarness.__getLatestPanHandlers().onEnd as
        | (((event: { translationX: number; velocityX: number }) => void) & {
          __workletHash?: number;
        })
        | undefined)?.__workletHash,
    ).toEqual(expect.any(Number));
    await drag(-40, -200);

    expect(getByTestId(left.renderer, 'main-scene-index')).toBeTruthy();
    expect(getByTestId(left.renderer, 'main-scene-you')).toBeTruthy();
    expect(queryByTestId(left.renderer, 'main-scene-chats')).toBeNull();
    expect(flattenedStyle(left.renderer, 'main-scene-index')).toMatchObject({ left: 0 });
    expect(flattenedStyle(left.renderer, 'main-scene-you')).toMatchObject({ left: 390 });
    expect(getByTestId(left.renderer, 'main-scene-you').props).toMatchObject({
      accessibilityElementsHidden: true,
      importantForAccessibility: 'no-hide-descendants',
      pointerEvents: 'none',
    });
    expect(flattenedStyle(left.renderer, 'main-scene-track')).toEqual({
      transform: [{ translateX: -39.2 }],
    });
    expect(left.renderMocks.chats).not.toHaveBeenCalled();

    const right = await renderNavigator();
    Object.values(right.renderMocks).forEach((mock) => mock.mockClear());
    await drag(40, 200);

    expect(getByTestId(right.renderer, 'main-scene-chats')).toBeTruthy();
    expect(getByTestId(right.renderer, 'main-scene-index')).toBeTruthy();
    expect(queryByTestId(right.renderer, 'main-scene-you')).toBeNull();
    expect(flattenedStyle(right.renderer, 'main-scene-chats')).toMatchObject({ left: -390 });
    expect(flattenedStyle(right.renderer, 'main-scene-index')).toMatchObject({ left: 0 });
    expect(right.renderMocks.you).not.toHaveBeenCalled();
  });

  test('keeps edge and four-route windows bounded to active plus one adjacent descriptor', async () => {
    const edge = await renderNavigator({ index: 0 });
    Object.values(edge.renderMocks).forEach((mock) => mock.mockClear());
    await drag(100, 200);

    expect(getByTestId(edge.renderer, 'main-scene-chats')).toBeTruthy();
    expect(queryByTestId(edge.renderer, 'main-scene-index')).toBeNull();
    expect(flattenedStyle(edge.renderer, 'main-scene-track')).toEqual({
      transform: [{ translateX: 18 }],
    });
    expect(edge.renderMocks.index).not.toHaveBeenCalled();
    expect(edge.renderMocks.you).not.toHaveBeenCalled();

    const routeNames = ['zero', 'one', 'two', 'three', 'four'];
    const scalable = await renderNavigator({ index: 2, routeNames });
    Object.values(scalable.renderMocks).forEach((mock) => mock.mockClear());
    await drag(-40, -200);

    expect(getByTestId(scalable.renderer, 'main-scene-two')).toBeTruthy();
    expect(getByTestId(scalable.renderer, 'main-scene-three')).toBeTruthy();
    expect(queryByTestId(scalable.renderer, 'main-scene-zero')).toBeNull();
    expect(queryByTestId(scalable.renderer, 'main-scene-one')).toBeNull();
    expect(queryByTestId(scalable.renderer, 'main-scene-four')).toBeNull();
    expect(scalable.renderMocks.zero).not.toHaveBeenCalled();
    expect(scalable.renderMocks.one).not.toHaveBeenCalled();
    expect(scalable.renderMocks.four).not.toHaveBeenCalled();
  });

  test('rolls cancellation back to the active descriptor and interaction origin', async () => {
    const { navigation, renderer } = await renderNavigator();
    await drag(-40, -300);

    await act(async () => {
      gestureHarness.__getLatestPanHandlers().onEnd?.({
        translationX: -40,
        velocityX: -300,
      });
      await Promise.resolve();
    });

    expect(mockWithSpring).toHaveBeenCalledWith(0, {
      damping: 30,
      stiffness: 340,
      overshootClamping: true,
    });
    expect(navigation.dispatch).not.toHaveBeenCalled();
    expect(queryByTestId(renderer, 'main-scene-you')).toBeNull();
    expect(capturedInteraction?.fromIndex.value).toBe(1);
    expect(capturedInteraction?.toIndex.value).toBe(-1);
    expect(capturedInteraction?.progress.value).toBe(0);
    expect(capturedInteraction?.interacting.value).toBe(0);
  });

  test('settles before dispatch and announces and focuses only after router confirmation', async () => {
    const { navigation, renderer, rerender } = await renderNavigator();
    await drag(-80, -200);

    await act(async () => {
      gestureHarness.__getLatestPanHandlers().onEnd?.({
        translationX: -80,
        velocityX: -200,
      });
      await Promise.resolve();
    });

    const settleCall = mockWithTiming.mock.calls.find(
      ([target, config]) => target === -390 && typeof config?.duration === 'number',
    );
    expect(settleCall?.[1]?.duration).toBeLessThanOrEqual(240);
    expect(navigation.dispatch).not.toHaveBeenCalled();
    expect(nativeHarness.AccessibilityInfo.announceForAccessibility).not.toHaveBeenCalled();

    await act(async () => {
      settleCall?.[2]?.(true);
      await Promise.resolve();
    });

    expect(navigation.dispatch).toHaveBeenCalledWith({
      type: 'NAVIGATE',
      payload: { name: 'you', merge: true },
    });
    expect(nativeHarness.AccessibilityInfo.announceForAccessibility).not.toHaveBeenCalled();

    await rerender(2);

    expect(queryByTestId(renderer, 'main-scene-index')).toBeNull();
    expect(getByTestId(renderer, 'main-scene-you')).toBeTruthy();
    expect(nativeHarness.AccessibilityInfo.announceForAccessibility).toHaveBeenCalledTimes(1);
    expect(nativeHarness.AccessibilityInfo.announceForAccessibility).toHaveBeenCalledWith('Me');
    expect(nativeHarness.AccessibilityInfo.setAccessibilityFocus).toHaveBeenCalledTimes(1);

    await rerender(2);
    expect(nativeHarness.AccessibilityInfo.announceForAccessibility).toHaveBeenCalledTimes(1);
    expect(nativeHarness.AccessibilityInfo.setAccessibilityFocus).toHaveBeenCalledTimes(1);
  });

  test('context navigation jumps directly with a white overlapping fade and no spatial traversal', async () => {
    const { navigation, renderer, rerender } = await renderNavigator({ index: 0 });

    await act(async () => {
      capturedInteraction?.navigate('you');
      await Promise.resolve();
    });

    expect(navigation.dispatch).toHaveBeenCalledTimes(1);
    expect(navigation.dispatch).toHaveBeenCalledWith({
      type: 'NAVIGATE',
      payload: { name: 'you', merge: true },
    });
    expect(mockWithTiming.mock.calls.some(([target]) => target === -390)).toBe(false);
    expect(nativeHarness.AccessibilityInfo.announceForAccessibility).not.toHaveBeenCalled();

    await rerender(2);

    expect(getByTestId(renderer, 'main-scene-chats')).toBeTruthy();
    expect(getByTestId(renderer, 'main-scene-you')).toBeTruthy();
    expect(queryByTestId(renderer, 'main-scene-index')).toBeNull();
    expect(getByTestId(renderer, 'main-scene-chats').props).toMatchObject({
      accessibilityElementsHidden: true,
      importantForAccessibility: 'no-hide-descendants',
      pointerEvents: 'none',
    });
    expect(getByTestId(renderer, 'main-scene-viewport').props.className).toContain('bg-white');
    expect(nativeHarness.AccessibilityInfo.announceForAccessibility).toHaveBeenCalledTimes(1);
    expect(nativeHarness.AccessibilityInfo.setAccessibilityFocus).not.toHaveBeenCalled();

    const fadeCallback = timingCallbackFor(1, 180);
    expect(fadeCallback).toEqual(expect.any(Function));
    await act(async () => {
      fadeCallback?.(true);
      await Promise.resolve();
    });

    expect(queryByTestId(renderer, 'main-scene-chats')).toBeNull();
    expect(getByTestId(renderer, 'main-scene-you')).toBeTruthy();
    expect(nativeHarness.AccessibilityInfo.setAccessibilityFocus).toHaveBeenCalledTimes(1);
  });

  test('disables spatial recognition for Reduced Motion while keeping direct fade navigation', async () => {
    const { navigation, renderer, rerender } = await renderNavigator({ reduceMotion: true });

    expect(gestureHarness.__getLatestPanConfig().enabled).toBe(false);

    await act(async () => {
      capturedInteraction?.navigate('chats');
      await Promise.resolve();
    });

    expect(navigation.dispatch).toHaveBeenCalledWith({
      type: 'NAVIGATE',
      payload: { name: 'chats', merge: true },
    });

    await rerender(0);

    expect(getByTestId(renderer, 'main-scene-index')).toBeTruthy();
    expect(getByTestId(renderer, 'main-scene-chats')).toBeTruthy();
    expect(timingCallbackFor(1, 180)).toEqual(expect.any(Function));
  });

  test('normalizes route replacement, viewport changes, and background interruptions', async () => {
    const routeNames = ['chats', 'index', 'you'];
    const routeKeys = buildRouteKeys(routeNames);
    const view = await renderNavigator({ routeNames, routeKeys });

    await drag(-40, -200);
    const replacedKeys = [...routeKeys];
    replacedKeys[1] = 'index-replaced-key';
    await view.rerender(1, routeNames, replacedKeys);

    expect(mockCancelAnimation).toHaveBeenCalledTimes(2);
    expect(capturedInteraction?.toIndex.value).toBe(-1);
    expect(capturedInteraction?.progress.value).toBe(0);
    expect(capturedInteraction?.interacting.value).toBe(0);
    expect(queryByTestId(view.renderer, 'main-scene-you')).toBeNull();

    jest.clearAllMocks();
    await drag(-40, -200);
    nativeHarness.__setViewportWidth(430);
    await view.rerender(1, routeNames, replacedKeys);

    expect(mockCancelAnimation).toHaveBeenCalledTimes(2);
    expect(capturedInteraction?.toIndex.value).toBe(-1);
    expect(capturedInteraction?.progress.value).toBe(0);

    jest.clearAllMocks();
    await drag(-40, -200);
    await act(async () => {
      nativeHarness.__emitAppState('background');
      await Promise.resolve();
    });

    expect(mockCancelAnimation).toHaveBeenCalledTimes(2);
    expect(capturedInteraction?.toIndex.value).toBe(-1);
    expect(capturedInteraction?.progress.value).toBe(0);
    expect(capturedInteraction?.interacting.value).toBe(0);
    expect(queryByTestId(view.renderer, 'main-scene-you')).toBeNull();
  });

  test('cancels an interrupted gesture without remounting the active descriptor subtree', async () => {
    const view = await renderNavigator();

    expect(view.mountMocks.index).toHaveBeenCalledTimes(1);
    expect(view.unmountMocks.index).not.toHaveBeenCalled();

    await drag(-40, -200);
    nativeHarness.__setViewportWidth(430);
    await view.rerender(1);

    expect(view.mountMocks.index).toHaveBeenCalledTimes(1);
    expect(view.unmountMocks.index).not.toHaveBeenCalled();
  });

  test('uses a route-authoritative custom navigator and a UI-worklet-safe end resolver', () => {
    const source = fs.readFileSync(
      path.resolve(__dirname, '../InteractiveMainNavigator.tsx'),
      'utf8',
    );

    expect(source).toMatch(/useNavigationBuilder<[\s\S]*?>\(TabRouter/);
    expect(source).toMatch(/\.onEnd\([\s\S]*resolveMainSwipe\(/);
    expect(source).toMatch(/withLayoutContext/);
    expect(source).not.toMatch(/react-native-pager-view/);
  });
});

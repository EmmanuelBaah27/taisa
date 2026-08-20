import {
  CommonActions,
  createNavigatorFactory,
  type ParamListBase,
  type TabActionHelpers,
  type TabNavigationState,
  TabRouter,
  type TabRouterOptions,
  useNavigationBuilder,
} from '@react-navigation/native';
import { withLayoutContext } from 'expo-router';
import {
  type ComponentRef,
  type ComponentType,
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
import {
  AccessibilityInfo,
  AppState,
  findNodeHandle,
  Text,
  useWindowDimensions,
  View,
} from 'react-native';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import Animated, {
  cancelAnimation,
  runOnJS,
  useAnimatedStyle,
  useSharedValue,
  withSpring,
  withTiming,
} from 'react-native-reanimated';

import { VoiceButton as DefaultVoiceButton } from '../components/VoiceButton';
import { BottomNavBar as DefaultBottomNavBar } from '../components/ui/BottomNavBar';
import { BOTTOM_NAVIGATION_ITEMS } from './bottomNavigation';
import {
  getMainSceneFrames,
  MAIN_EDGE_RESISTANCE,
  type MainDestinationId,
  MAIN_SWIPE_TRACKING,
  resolveMainSwipe,
} from './interactiveMainNavigation';
import { MainNavigationInteractionContext } from './MainNavigationInteractionContext';

export type InteractiveMainNavigationOptions = Record<string, never>;

export type InteractiveMainNavigationEventMap = {
  tabPress: { data: undefined; canPreventDefault: true };
};

type InteractiveMainNavigationBuilder = ReturnType<
  typeof useNavigationBuilder<
    TabNavigationState<ParamListBase>,
    TabRouterOptions,
    TabActionHelpers<ParamListBase>,
    InteractiveMainNavigationOptions,
    InteractiveMainNavigationEventMap
  >
>;

type InteractiveMainNavigatorProps = Parameters<
  typeof useNavigationBuilder<
    TabNavigationState<ParamListBase>,
    TabRouterOptions,
    TabActionHelpers<ParamListBase>,
    InteractiveMainNavigationOptions,
    InteractiveMainNavigationEventMap
  >
>[1];

export interface InteractiveMainNavigatorViewProps {
  state: InteractiveMainNavigationBuilder['state'];
  navigation: InteractiveMainNavigationBuilder['navigation'];
  descriptors: InteractiveMainNavigationBuilder['descriptors'];
  BottomNavBar?: ComponentType;
  VoiceButton?: ComponentType;
}

type SceneDirection = -1 | 0 | 1;

const CANCEL_SPRING = {
  damping: 30,
  stiffness: 340,
  overshootClamping: true,
} as const;
const MAIN_SETTLE_DURATION = 220;
const MAIN_FADE_DURATION = 180;

function getRouteLabel(routeName: string): string {
  return BOTTOM_NAVIGATION_ITEMS.find((item) => item.id === routeName)?.label
    ?? routeName;
}

export function InteractiveMainNavigatorView({
  state,
  navigation,
  descriptors,
  BottomNavBar = DefaultBottomNavBar,
  VoiceButton = DefaultVoiceButton,
}: InteractiveMainNavigatorViewProps) {
  const { width: viewportWidth } = useWindowDimensions();
  const activeIndex = state.index;
  const activeRoute = state.routes[activeIndex];
  const activeRouteKey = activeRoute.key;
  const activeRouteName = activeRoute.name;
  const routeNames = useMemo(
    () => state.routes.map((route) => route.name),
    [state.routes],
  );
  const descriptorAvailability = useMemo(
    () => state.routes.map((route) => descriptors[route.key] !== undefined),
    [descriptors, state.routes],
  );

  const trackX = useSharedValue(0);
  const fadeProgress = useSharedValue(1);
  const gestureDirectionValue = useSharedValue<SceneDirection>(0);
  const swipeProgress = useSharedValue(0);
  const swipeFromIndex = useSharedValue(activeIndex);
  const swipeToIndex = useSharedValue(-1);
  const swipeInteracting = useSharedValue(0);
  const [gestureDirection, setGestureDirection] = useState<SceneDirection>(0);
  const [gestureEnabled, setGestureEnabled] = useState(true);
  const [reduceMotion, setReduceMotion] = useState(false);
  const [fadeFromRouteKey, setFadeFromRouteKey] = useState<string | null>(null);
  const headingRefs = useRef<Record<string, ComponentRef<typeof Text> | null>>({});
  const previousLayoutRef = useRef({
    activeIndex,
    activeRouteKey,
    viewportWidth,
  });
  const committedRouteRef = useRef({
    key: activeRouteKey,
    name: activeRouteName,
  });

  const normalizeSpatialInteraction = useCallback((nextActiveIndex: number) => {
    cancelAnimation(trackX);
    cancelAnimation(swipeProgress);
    trackX.value = 0;
    gestureDirectionValue.value = 0;
    swipeProgress.value = 0;
    swipeFromIndex.value = nextActiveIndex;
    swipeToIndex.value = -1;
    swipeInteracting.value = 0;
    setGestureDirection(0);
    // Updating an active handler to disabled cancels it without remounting its
    // route subtree. A passive effect restores readiness after that commit.
    setGestureEnabled(false);
  }, [
    gestureDirectionValue,
    swipeFromIndex,
    swipeInteracting,
    swipeProgress,
    swipeToIndex,
    trackX,
  ]);

  const normalizeInterruption = useCallback(() => {
    normalizeSpatialInteraction(state.index);
    if (fadeFromRouteKey !== null) {
      cancelAnimation(fadeProgress);
      fadeProgress.value = 1;
      setFadeFromRouteKey(null);
    }
  }, [fadeFromRouteKey, fadeProgress, normalizeSpatialInteraction, state.index]);

  const focusSceneHeading = useCallback((routeKey: string) => {
    const nativeHandle = findNodeHandle(headingRefs.current[routeKey]);
    if (nativeHandle !== null) {
      AccessibilityInfo.setAccessibilityFocus(nativeHandle);
    }
  }, []);

  const finishDirectFade = useCallback((destinationRouteKey: string) => {
    fadeProgress.value = 1;
    setFadeFromRouteKey(null);
    focusSceneHeading(destinationRouteKey);
  }, [fadeProgress, focusSceneHeading]);

  const finishGestureCancellation = useCallback(() => {
    gestureDirectionValue.value = 0;
    swipeProgress.value = 0;
    swipeFromIndex.value = state.index;
    swipeToIndex.value = -1;
    swipeInteracting.value = 0;
    setGestureDirection(0);
  }, [
    gestureDirectionValue,
    state.index,
    swipeFromIndex,
    swipeInteracting,
    swipeProgress,
    swipeToIndex,
  ]);

  const updateGestureDirection = useCallback((direction: SceneDirection) => {
    setGestureDirection(direction);
  }, []);

  const dispatchRoute = useCallback((destinationIndex: number) => {
    const destination = state.routes[destinationIndex];
    if (!destination || !descriptors[destination.key]) return;

    navigation.dispatch(CommonActions.navigate({
      name: destination.name,
      merge: true,
    }));
  }, [descriptors, navigation, state.routes]);

  const navigate = useCallback((destinationId: MainDestinationId) => {
    const destinationIndex = state.routes.findIndex(
      (route) => route.name === destinationId,
    );
    if (destinationIndex < 0 || destinationIndex === state.index) return;

    const destination = state.routes[destinationIndex];
    if (!descriptors[destination.key]) return;

    cancelAnimation(fadeProgress);
    fadeProgress.value = 0;
    setFadeFromRouteKey(activeRouteKey);
    navigation.dispatch(CommonActions.navigate({
      name: destination.name,
      merge: true,
    }));
  }, [
    activeRouteKey,
    descriptors,
    fadeProgress,
    navigation,
    state.index,
    state.routes,
  ]);

  useLayoutEffect(() => {
    const previous = previousLayoutRef.current;
    const routeReplaced = previous.activeRouteKey !== activeRouteKey;
    const indexChanged = previous.activeIndex !== activeIndex;
    const viewportChanged = previous.viewportWidth !== viewportWidth;

    if (routeReplaced || indexChanged || viewportChanged) {
      normalizeSpatialInteraction(activeIndex);
    }

    previousLayoutRef.current = {
      activeIndex,
      activeRouteKey,
      viewportWidth,
    };
  }, [
    activeIndex,
    activeRouteKey,
    normalizeSpatialInteraction,
    viewportWidth,
  ]);

  useEffect(() => {
    if (!gestureEnabled) setGestureEnabled(true);
  }, [gestureEnabled]);

  useEffect(() => {
    let mounted = true;
    AccessibilityInfo.isReduceMotionEnabled().then((enabled) => {
      if (mounted) setReduceMotion(enabled);
    });
    const motionSubscription = AccessibilityInfo.addEventListener(
      'reduceMotionChanged',
      setReduceMotion,
    );

    return () => {
      mounted = false;
      motionSubscription.remove();
    };
  }, []);

  useEffect(() => {
    const appSubscription = AppState.addEventListener('change', (nextState) => {
      if (nextState !== 'active') normalizeInterruption();
    });

    return () => appSubscription.remove();
  }, [normalizeInterruption]);

  const fadeFromRoute = fadeFromRouteKey === null
    ? undefined
    : state.routes.find((route) => route.key === fadeFromRouteKey);
  const isDirectFade = fadeFromRoute !== undefined
    && fadeFromRoute.key !== activeRouteKey
    && descriptors[fadeFromRoute.key] !== undefined;

  useEffect(() => {
    const previousCommittedRoute = committedRouteRef.current;
    if (previousCommittedRoute.key === activeRouteKey) return;

    committedRouteRef.current = {
      key: activeRouteKey,
      name: activeRouteName,
    };
    const destinationChanged = previousCommittedRoute.name !== activeRouteName;

    if (!destinationChanged) {
      if (fadeFromRouteKey !== null) {
        fadeProgress.value = 1;
        setFadeFromRouteKey(null);
      }
      return;
    }

    AccessibilityInfo.announceForAccessibility(getRouteLabel(activeRouteName));

    if (isDirectFade) {
      fadeProgress.value = 0;
      fadeProgress.value = withTiming(
        1,
        { duration: MAIN_FADE_DURATION },
        (finished) => {
          if (finished) runOnJS(finishDirectFade)(activeRouteKey);
        },
      );
      return;
    }

    focusSceneHeading(activeRouteKey);
  }, [
    activeRouteKey,
    activeRouteName,
    fadeFromRouteKey,
    fadeProgress,
    finishDirectFade,
    focusSceneHeading,
    isDirectFade,
  ]);

  const horizontalPan = useMemo(() => Gesture.Pan()
    .enabled(gestureEnabled && !reduceMotion && fadeFromRouteKey === null)
    .activeOffsetX([-18, 18])
    .failOffsetY([-14, 14])
    .cancelsTouchesInView(true)
    .onBegin(() => {
      gestureDirectionValue.value = 0;
      swipeFromIndex.value = activeIndex;
      swipeToIndex.value = -1;
      swipeProgress.value = 0;
      swipeInteracting.value = 1;
    })
    .onUpdate((event) => {
      const direction: SceneDirection = event.translationX < 0
        ? 1
        : event.translationX > 0
          ? -1
          : 0;
      if (direction !== gestureDirectionValue.value) {
        gestureDirectionValue.value = direction;
        runOnJS(updateGestureDirection)(direction);
      }

      const destinationIndex = activeIndex + direction;
      const destinationAvailable = direction !== 0
        && destinationIndex >= 0
        && destinationIndex < state.routes.length
        && descriptorAvailability[destinationIndex];
      const edge = direction !== 0 && !destinationAvailable;
      trackX.value = event.translationX
        * (edge ? MAIN_EDGE_RESISTANCE : MAIN_SWIPE_TRACKING);
      swipeToIndex.value = destinationAvailable ? destinationIndex : -1;
      swipeProgress.value = edge || viewportWidth <= 0
        ? 0
        : Math.min(Math.abs(trackX.value) / viewportWidth, 1);
    })
    .onEnd((event) => {
      const resolution = resolveMainSwipe({
        activeIndex,
        routeCount: state.routes.length,
        translationX: event.translationX,
        velocityX: event.velocityX,
      });
      const destinationAvailable = resolution.kind === 'commit'
        && descriptorAvailability[resolution.destinationIndex];

      if (resolution.kind === 'cancel' || !destinationAvailable) {
        trackX.value = withSpring(0, CANCEL_SPRING);
        swipeProgress.value = withSpring(
          0,
          CANCEL_SPRING,
          (finished) => {
            if (finished) runOnJS(finishGestureCancellation)();
          },
        );
        return;
      }

      trackX.value = withTiming(
        resolution.direction * -viewportWidth,
        { duration: MAIN_SETTLE_DURATION },
        (finished) => {
          if (finished) runOnJS(dispatchRoute)(resolution.destinationIndex);
        },
      );
      swipeProgress.value = withTiming(1, {
        duration: MAIN_SETTLE_DURATION,
      });
    })
    .onFinalize((_event, success) => {
      if (success) return;

      trackX.value = withSpring(0, CANCEL_SPRING);
      swipeProgress.value = withSpring(
        0,
        CANCEL_SPRING,
        (finished) => {
          if (finished) runOnJS(finishGestureCancellation)();
        },
      );
    }), [
    activeIndex,
    descriptorAvailability,
    dispatchRoute,
    fadeFromRouteKey,
    finishGestureCancellation,
    gestureEnabled,
    gestureDirectionValue,
    reduceMotion,
    state.routes.length,
    swipeFromIndex,
    swipeInteracting,
    swipeProgress,
    swipeToIndex,
    trackX,
    updateGestureDirection,
    viewportWidth,
  ]);

  const trackStyle = useAnimatedStyle(() => ({
    transform: [{ translateX: trackX.value }],
  }));
  const fadeOutgoingStyle = useAnimatedStyle(() => ({
    opacity: 1 - fadeProgress.value,
  }));
  const fadeIncomingStyle = useAnimatedStyle(() => ({
    opacity: fadeProgress.value,
  }));

  const sceneFrames = getMainSceneFrames(
    routeNames,
    activeIndex,
    gestureDirection,
    viewportWidth,
  );
  const interactionValue = useMemo(() => ({
    activeIndex,
    progress: swipeProgress,
    fromIndex: swipeFromIndex,
    toIndex: swipeToIndex,
    interacting: swipeInteracting,
    navigate,
  }), [
    activeIndex,
    navigate,
    swipeFromIndex,
    swipeInteracting,
    swipeProgress,
    swipeToIndex,
  ]);

  const activeHeading = (routeKey: string, routeName: string) => (
    <Text
      ref={(node) => { headingRefs.current[routeKey] = node; }}
      accessibilityRole="header"
      className="absolute h-px w-px overflow-hidden opacity-0"
    >
      {getRouteLabel(routeName)}
    </Text>
  );

  const sceneViewport = (
    <View
      className="flex-1 overflow-hidden bg-white"
      testID="main-scene-viewport"
    >
      {isDirectFade && fadeFromRoute ? (
        <View className="flex-1" testID="main-scene-fade">
          <Animated.View
            accessibilityElementsHidden
            importantForAccessibility="no-hide-descendants"
            pointerEvents="none"
            testID={`main-scene-${fadeFromRoute.name}`}
            className="absolute inset-0"
            style={fadeOutgoingStyle}
          >
            {descriptors[fadeFromRoute.key].render()}
          </Animated.View>
          <Animated.View
            accessibilityElementsHidden={false}
            importantForAccessibility="auto"
            pointerEvents="auto"
            testID={`main-scene-${activeRouteName}`}
            className="absolute inset-0"
            style={fadeIncomingStyle}
          >
            {activeHeading(activeRouteKey, activeRouteName)}
            {descriptors[activeRouteKey].render()}
          </Animated.View>
        </View>
      ) : (
        <Animated.View
          className="absolute inset-0"
          testID="main-scene-track"
          style={trackStyle}
        >
          {sceneFrames.map((frame) => {
            const route = state.routes[frame.index];
            const descriptor = descriptors[route.key];
            if (!descriptor) return null;

            const active = frame.index === activeIndex;
            return (
              <View
                key={route.key}
                accessibilityElementsHidden={!active}
                importantForAccessibility={active ? 'auto' : 'no-hide-descendants'}
                pointerEvents={active ? 'auto' : 'none'}
                testID={`main-scene-${route.name}`}
                className="absolute inset-y-0"
                style={{
                  left: frame.left,
                  width: viewportWidth,
                }}
              >
                {active ? activeHeading(route.key, route.name) : null}
                {descriptor.render()}
              </View>
            );
          })}
        </Animated.View>
      )}
    </View>
  );

  return (
    <MainNavigationInteractionContext.Provider value={interactionValue}>
      <GestureDetector
        gesture={horizontalPan}
      >
        <Animated.View
          collapsable={false}
          className="flex-1"
          testID="main-navigation-shell"
        >
          {sceneViewport}
          <BottomNavBar />
          <VoiceButton />
        </Animated.View>
      </GestureDetector>
    </MainNavigationInteractionContext.Provider>
  );
}

function InteractiveMainNavigatorBase({
  id,
  initialRouteName,
  children,
  screenListeners,
  screenOptions,
}: InteractiveMainNavigatorProps) {
  const { state, navigation, descriptors, NavigationContent } =
    useNavigationBuilder<
      TabNavigationState<ParamListBase>,
      TabRouterOptions,
      TabActionHelpers<ParamListBase>,
      InteractiveMainNavigationOptions,
      InteractiveMainNavigationEventMap
    >(TabRouter, {
      id,
      initialRouteName,
      children,
      screenListeners,
      screenOptions,
    });

  return (
    <NavigationContent>
      <InteractiveMainNavigatorView
        state={state}
        navigation={navigation}
        descriptors={descriptors}
      />
    </NavigationContent>
  );
}

const InteractiveMainNavigatorFactory = createNavigatorFactory(
  InteractiveMainNavigatorBase,
)();

export const InteractiveMainNavigator = withLayoutContext<
  InteractiveMainNavigationOptions,
  typeof InteractiveMainNavigatorFactory.Navigator,
  TabNavigationState<ParamListBase>,
  InteractiveMainNavigationEventMap
>(InteractiveMainNavigatorFactory.Navigator);

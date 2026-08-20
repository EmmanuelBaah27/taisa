import {
  CommonActions, createNavigatorFactory, type ParamListBase, type TabActionHelpers,
  type TabNavigationState, TabRouter, type TabRouterOptions, useNavigationBuilder,
} from '@react-navigation/native';
import { withLayoutContext } from 'expo-router';
import {
  type ComponentRef, type ComponentType, useCallback, useEffect, useMemo, useRef, useState,
} from 'react';
import {
  AccessibilityInfo, AppState, type NativeScrollEvent, type NativeSyntheticEvent,
  useWindowDimensions, View,
} from 'react-native';
import Animated, {
  runOnJS,
  useAnimatedScrollHandler,
  useAnimatedStyle,
  useSharedValue,
  withTiming,
} from 'react-native-reanimated';

import { VoiceButton as DefaultVoiceButton } from '../components/VoiceButton';
import { BottomNavBar as DefaultBottomNavBar } from '../components/ui/BottomNavBar';
import { playInteractionHaptic } from '../services/interactionHaptics';
import { BOTTOM_NAVIGATION_ITEMS } from './bottomNavigation';
import type { MainDestinationId } from './interactiveMainNavigation';
import { MainNavigationInteractionContext } from './MainNavigationInteractionContext';

export type InteractiveMainNavigationOptions = Record<string, never>;
export type InteractiveMainNavigationEventMap = {
  tabPress: { data: undefined; canPreventDefault: true };
};
type Builder = ReturnType<typeof useNavigationBuilder<
  TabNavigationState<ParamListBase>, TabRouterOptions, TabActionHelpers<ParamListBase>,
  InteractiveMainNavigationOptions, InteractiveMainNavigationEventMap
>>;
type Props = Parameters<typeof useNavigationBuilder<
  TabNavigationState<ParamListBase>, TabRouterOptions, TabActionHelpers<ParamListBase>,
  InteractiveMainNavigationOptions, InteractiveMainNavigationEventMap
>>[1];

export interface InteractiveMainNavigatorViewProps {
  state: Builder['state'];
  navigation: Builder['navigation'];
  descriptors: Builder['descriptors'];
  BottomNavBar?: ComponentType;
  VoiceButton?: ComponentType;
}

function routeLabel(routeName: string): string {
  return BOTTOM_NAVIGATION_ITEMS.find((item) => item.id === routeName)?.label ?? routeName;
}

export function InteractiveMainNavigatorView({
  state, navigation, descriptors,
  BottomNavBar = DefaultBottomNavBar,
  VoiceButton = DefaultVoiceButton,
}: InteractiveMainNavigatorViewProps) {
  const scrollRef = useRef<ComponentRef<typeof Animated.ScrollView>>(null);
  const { width: pageWidth } = useWindowDimensions();
  const activeIndex = state.index;
  const activeIndexValue = useSharedValue(activeIndex);
  const swipeProgress = useSharedValue(0);
  const swipeFromIndex = useSharedValue(activeIndex);
  const swipeToIndex = useSharedValue(-1);
  const swipeInteracting = useSharedValue(0);
  const directTransition = useSharedValue(0);
  const directPageOpacity = useSharedValue(1);
  const pendingIndexRef = useRef<number | null>(null);
  const [reduceMotion, setReduceMotion] = useState(false);

  useEffect(() => {
    activeIndexValue.value = activeIndex;
    swipeFromIndex.value = activeIndex;
    swipeToIndex.value = -1;
    swipeProgress.value = 0;
    swipeInteracting.value = 0;
    directTransition.value = 0;
    directPageOpacity.value = 1;
    if (pendingIndexRef.current === activeIndex) {
      pendingIndexRef.current = null;
      return;
    }
    scrollRef.current?.scrollTo({ x: activeIndex * pageWidth, animated: false });
  }, [activeIndex, activeIndexValue, directPageOpacity, directTransition, pageWidth, swipeFromIndex, swipeInteracting, swipeProgress, swipeToIndex]);

  useEffect(() => {
    let mounted = true;
    AccessibilityInfo.isReduceMotionEnabled().then((enabled) => {
      if (mounted) setReduceMotion(enabled);
    });
    const motion = AccessibilityInfo.addEventListener('reduceMotionChanged', setReduceMotion);
    const appState = AppState.addEventListener('change', (nextState) => {
      if (nextState === 'active') return;
      pendingIndexRef.current = null;
      scrollRef.current?.scrollTo({ x: activeIndexValue.value * pageWidth, animated: false });
      swipeProgress.value = 0;
      swipeToIndex.value = -1;
      swipeInteracting.value = 0;
    });
    return () => {
      mounted = false;
      motion.remove();
      appState.remove();
    };
  }, [activeIndexValue, pageWidth, swipeInteracting, swipeProgress, swipeToIndex]);

  const pageScrollHandler = useAnimatedScrollHandler({
    onScroll: (event) => {
      'worklet';
      if (directTransition.value === 1) return;
      const pagePosition = event.contentOffset.x / pageWidth;
      const origin = activeIndexValue.value;
      const delta = pagePosition - origin;
      swipeFromIndex.value = origin;
      swipeToIndex.value = delta < 0 ? origin - 1 : delta > 0 ? origin + 1 : -1;
      swipeProgress.value = Math.min(Math.abs(delta), 1);
    },
    onBeginDrag: () => {
      swipeInteracting.value = 1;
      swipeFromIndex.value = activeIndexValue.value;
    },
  });
  const directPageStyle = useAnimatedStyle(() => ({ opacity: directPageOpacity.value }));

  const dispatchRoute = useCallback((destinationIndex: number) => {
    const destination = state.routes[destinationIndex];
    if (!destination || !descriptors[destination.key]) return;
    pendingIndexRef.current = destinationIndex;
    playInteractionHaptic('selection');
    navigation.dispatch(CommonActions.navigate({ name: destination.name, merge: true }));
    AccessibilityInfo.announceForAccessibility(routeLabel(destination.name));
  }, [descriptors, navigation, state.routes]);

  const onPageSelected = useCallback((event: NativeSyntheticEvent<NativeScrollEvent>) => {
    const destinationIndex = Math.round(event.nativeEvent.contentOffset.x / pageWidth);
    if (destinationIndex !== state.index) {
      swipeFromIndex.value = destinationIndex;
      swipeToIndex.value = destinationIndex;
      swipeProgress.value = 0;
      swipeInteracting.value = 1;
      dispatchRoute(destinationIndex);
      return;
    }
    swipeProgress.value = 0;
    swipeToIndex.value = -1;
    swipeInteracting.value = 0;
  }, [dispatchRoute, pageWidth, state.index, swipeFromIndex, swipeInteracting, swipeProgress, swipeToIndex]);

  const jumpDirectlyToPage = useCallback((destinationIndex: number) => {
    scrollRef.current?.scrollTo({ x: destinationIndex * pageWidth, animated: false });
  }, [pageWidth]);

  const navigate = useCallback((destinationId: MainDestinationId) => {
    const destinationIndex = state.routes.findIndex((route) => route.name === destinationId);
    if (destinationIndex < 0 || destinationIndex === state.index) return;
    const destination = state.routes[destinationIndex];
    if (!descriptors[destination.key]) return;
    pendingIndexRef.current = destinationIndex;
    swipeFromIndex.value = state.index;
    swipeToIndex.value = destinationIndex;
    swipeInteracting.value = 1;
    const nonAdjacent = Math.abs(destinationIndex - state.index) > 1;
    if (nonAdjacent && !reduceMotion) {
      directTransition.value = 1;
      directPageOpacity.value = withTiming(0, { duration: 90 }, (finished) => {
        if (!finished) return;
        runOnJS(jumpDirectlyToPage)(destinationIndex);
        directPageOpacity.value = withTiming(1, { duration: 170 });
      });
      swipeProgress.value = withTiming(1, { duration: 260 }, (finished) => {
        if (finished) runOnJS(dispatchRoute)(destinationIndex);
      });
      return;
    }
    if (reduceMotion) {
      scrollRef.current?.scrollTo({ x: destinationIndex * pageWidth, animated: false });
      dispatchRoute(destinationIndex);
    } else {
      scrollRef.current?.scrollTo({ x: destinationIndex * pageWidth, animated: true });
    }
  }, [descriptors, directPageOpacity, directTransition, dispatchRoute, jumpDirectlyToPage, pageWidth, reduceMotion, state.index, state.routes, swipeFromIndex, swipeInteracting, swipeProgress, swipeToIndex]);

  const interactionValue = useMemo(() => ({
    activeIndex, progress: swipeProgress, fromIndex: swipeFromIndex,
    toIndex: swipeToIndex, interacting: swipeInteracting, navigate,
  }), [activeIndex, navigate, swipeFromIndex, swipeInteracting, swipeProgress, swipeToIndex]);

  return (
    <MainNavigationInteractionContext.Provider value={interactionValue}>
      <View className="flex-1" testID="main-navigation-shell">
        <Animated.ScrollView
          ref={scrollRef}
          horizontal
          pagingEnabled
          bounces
          directionalLockEnabled
          decelerationRate="fast"
          onMomentumScrollEnd={onPageSelected}
          onScroll={pageScrollHandler}
          scrollEventThrottle={16}
          scrollEnabled={!reduceMotion}
          showsHorizontalScrollIndicator={false}
          style={[{ flex: 1 }, directPageStyle]}
          testID="main-scene-pager"
        >
          {state.routes.map((route, routeIndex) => (
            <View
              key={route.key}
              collapsable={false}
              accessibilityElementsHidden={routeIndex !== activeIndex}
              importantForAccessibility={routeIndex === activeIndex ? 'auto' : 'no-hide-descendants'}
              style={{ width: pageWidth }}
              testID={`main-scene-${route.name}`}
            >
              {descriptors[route.key]?.render()}
            </View>
          ))}
        </Animated.ScrollView>
        <BottomNavBar />
        <VoiceButton />
      </View>
    </MainNavigationInteractionContext.Provider>
  );
}

function InteractiveMainNavigatorBase({ id, initialRouteName, children, screenListeners, screenOptions }: Props) {
  const { state, navigation, descriptors, NavigationContent } = useNavigationBuilder<
    TabNavigationState<ParamListBase>, TabRouterOptions, TabActionHelpers<ParamListBase>,
    InteractiveMainNavigationOptions, InteractiveMainNavigationEventMap
  >(TabRouter, { id, initialRouteName, children, screenListeners, screenOptions });
  return (
    <NavigationContent>
      <InteractiveMainNavigatorView state={state} navigation={navigation} descriptors={descriptors} />
    </NavigationContent>
  );
}

const Factory = createNavigatorFactory(InteractiveMainNavigatorBase)();
export const InteractiveMainNavigator = withLayoutContext<
  InteractiveMainNavigationOptions, typeof Factory.Navigator,
  TabNavigationState<ParamListBase>, InteractiveMainNavigationEventMap
>(Factory.Navigator);

import {
  CommonActions, createNavigatorFactory, type ParamListBase, type TabActionHelpers,
  type TabNavigationState, TabRouter, type TabRouterOptions, useNavigationBuilder,
} from '@react-navigation/native';
import { withLayoutContext } from 'expo-router';
import { type ComponentType, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { AccessibilityInfo, AppState, View } from 'react-native';
import PagerView, {
  type PagerViewOnPageScrollEvent, type PagerViewOnPageSelectedEvent,
} from 'react-native-pager-view';
import Animated, { useEvent, useHandler, useSharedValue } from 'react-native-reanimated';

import { VoiceButton as DefaultVoiceButton } from '../components/VoiceButton';
import { BottomNavBar as DefaultBottomNavBar } from '../components/ui/BottomNavBar';
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

type PageScrollContext = Record<string, never>;
type PageScrollHandler = (event: PagerViewOnPageScrollEvent['nativeEvent']) => void;
const AnimatedPagerView = Animated.createAnimatedComponent(PagerView);

function useNativePageScroll(onPageScroll: PageScrollHandler) {
  const { doDependenciesDiffer } = useHandler<
    PagerViewOnPageScrollEvent['nativeEvent'], PageScrollContext
  >(
    { onPageScroll }, [onPageScroll],
  );
  return useEvent<PagerViewOnPageScrollEvent['nativeEvent'], PageScrollContext>((event) => {
    'worklet';
    if (event.eventName.endsWith('onPageScroll')) onPageScroll(event);
  }, ['onPageScroll'], doDependenciesDiffer);
}

function routeLabel(routeName: string): string {
  return BOTTOM_NAVIGATION_ITEMS.find((item) => item.id === routeName)?.label ?? routeName;
}

export function InteractiveMainNavigatorView({
  state, navigation, descriptors,
  BottomNavBar = DefaultBottomNavBar,
  VoiceButton = DefaultVoiceButton,
}: InteractiveMainNavigatorViewProps) {
  const pagerRef = useRef<PagerView>(null);
  const activeIndex = state.index;
  const activeIndexValue = useSharedValue(activeIndex);
  const swipeProgress = useSharedValue(0);
  const swipeFromIndex = useSharedValue(activeIndex);
  const swipeToIndex = useSharedValue(-1);
  const swipeInteracting = useSharedValue(0);
  const pendingIndexRef = useRef<number | null>(null);
  const [reduceMotion, setReduceMotion] = useState(false);

  useEffect(() => {
    activeIndexValue.value = activeIndex;
    swipeFromIndex.value = activeIndex;
    swipeToIndex.value = -1;
    swipeProgress.value = 0;
    swipeInteracting.value = 0;
    if (pendingIndexRef.current === activeIndex) {
      pendingIndexRef.current = null;
      return;
    }
    pagerRef.current?.setPageWithoutAnimation(activeIndex);
  }, [activeIndex, activeIndexValue, swipeFromIndex, swipeInteracting, swipeProgress, swipeToIndex]);

  useEffect(() => {
    let mounted = true;
    AccessibilityInfo.isReduceMotionEnabled().then((enabled) => {
      if (mounted) setReduceMotion(enabled);
    });
    const motion = AccessibilityInfo.addEventListener('reduceMotionChanged', setReduceMotion);
    const appState = AppState.addEventListener('change', (nextState) => {
      if (nextState === 'active') return;
      pendingIndexRef.current = null;
      pagerRef.current?.setPageWithoutAnimation(activeIndexValue.value);
      swipeProgress.value = 0;
      swipeToIndex.value = -1;
      swipeInteracting.value = 0;
    });
    return () => {
      mounted = false;
      motion.remove();
      appState.remove();
    };
  }, [activeIndexValue, swipeInteracting, swipeProgress, swipeToIndex]);

  const onPageScroll = useCallback<PageScrollHandler>((event) => {
    'worklet';
    const pagePosition = event.position + event.offset;
    const origin = activeIndexValue.value;
    const delta = pagePosition - origin;
    swipeFromIndex.value = origin;
    swipeToIndex.value = delta < 0 ? origin - 1 : delta > 0 ? origin + 1 : -1;
    swipeProgress.value = Math.min(Math.abs(delta), 1);
  }, [activeIndexValue, swipeFromIndex, swipeProgress, swipeToIndex]);
  const pageScrollHandler = useNativePageScroll(onPageScroll) as unknown as (
    event: PagerViewOnPageScrollEvent
  ) => void;

  const dispatchRoute = useCallback((destinationIndex: number) => {
    const destination = state.routes[destinationIndex];
    if (!destination || !descriptors[destination.key]) return;
    pendingIndexRef.current = destinationIndex;
    navigation.dispatch(CommonActions.navigate({ name: destination.name, merge: true }));
    AccessibilityInfo.announceForAccessibility(routeLabel(destination.name));
  }, [descriptors, navigation, state.routes]);

  const onPageSelected = useCallback((event: PagerViewOnPageSelectedEvent) => {
    const destinationIndex = event.nativeEvent.position;
    swipeProgress.value = 0;
    swipeToIndex.value = -1;
    swipeInteracting.value = 0;
    if (destinationIndex !== state.index) dispatchRoute(destinationIndex);
  }, [dispatchRoute, state.index, swipeInteracting, swipeProgress, swipeToIndex]);

  const navigate = useCallback((destinationId: MainDestinationId) => {
    const destinationIndex = state.routes.findIndex((route) => route.name === destinationId);
    if (destinationIndex < 0 || destinationIndex === state.index) return;
    const destination = state.routes[destinationIndex];
    if (!descriptors[destination.key]) return;
    pendingIndexRef.current = destinationIndex;
    swipeFromIndex.value = state.index;
    swipeToIndex.value = destinationIndex;
    swipeInteracting.value = 1;
    if (reduceMotion) {
      pagerRef.current?.setPageWithoutAnimation(destinationIndex);
      dispatchRoute(destinationIndex);
    } else {
      pagerRef.current?.setPage(destinationIndex);
    }
  }, [descriptors, dispatchRoute, reduceMotion, state.index, state.routes, swipeFromIndex, swipeInteracting, swipeToIndex]);

  const interactionValue = useMemo(() => ({
    activeIndex, progress: swipeProgress, fromIndex: swipeFromIndex,
    toIndex: swipeToIndex, interacting: swipeInteracting, navigate,
  }), [activeIndex, navigate, swipeFromIndex, swipeInteracting, swipeProgress, swipeToIndex]);

  return (
    <MainNavigationInteractionContext.Provider value={interactionValue}>
      <View className="flex-1" testID="main-navigation-shell">
        <AnimatedPagerView
          ref={pagerRef}
          initialPage={activeIndex}
          onPageScroll={pageScrollHandler}
          onPageSelected={onPageSelected}
          onPageScrollStateChanged={(event) => {
            const interacting = event.nativeEvent.pageScrollState !== 'idle';
            swipeInteracting.value = interacting ? 1 : 0;
            if (interacting) swipeFromIndex.value = state.index;
          }}
          orientation="horizontal"
          overdrag
          scrollEnabled={!reduceMotion}
          style={{ flex: 1 }}
          testID="main-scene-pager"
        >
          {state.routes.map((route, routeIndex) => (
            <View
              key={route.key}
              collapsable={false}
              accessibilityElementsHidden={routeIndex !== activeIndex}
              importantForAccessibility={routeIndex === activeIndex ? 'auto' : 'no-hide-descendants'}
              testID={`main-scene-${route.name}`}
            >
              {descriptors[route.key]?.render()}
            </View>
          ))}
        </AnimatedPagerView>
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

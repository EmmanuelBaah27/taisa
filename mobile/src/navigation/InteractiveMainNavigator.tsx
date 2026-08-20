import {
  CommonActions, createNavigatorFactory, type ParamListBase, type TabActionHelpers,
  type TabNavigationState, TabRouter, type TabRouterOptions, useNavigationBuilder,
} from '@react-navigation/native';
import { withLayoutContext } from 'expo-router';
import { type ComponentType, useCallback, useEffect, useMemo, useState } from 'react';
import { AccessibilityInfo, AppState, useWindowDimensions, View } from 'react-native';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import Animated, {
  cancelAnimation, runOnJS, useAnimatedStyle, useSharedValue, withSpring, withTiming,
} from 'react-native-reanimated';

import { VoiceButton as DefaultVoiceButton } from '../components/VoiceButton';
import { BottomNavBar as DefaultBottomNavBar } from '../components/ui/BottomNavBar';
import { BOTTOM_NAVIGATION_ITEMS } from './bottomNavigation';
import { MAIN_EDGE_RESISTANCE, MAIN_SWIPE_TRACKING, resolveMainSwipe } from './interactiveMainNavigation';
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

const CANCEL_SPRING = { damping: 30, stiffness: 340, overshootClamping: true };

export function InteractiveMainNavigatorView({
  state, navigation, descriptors,
  BottomNavBar = DefaultBottomNavBar,
  VoiceButton = DefaultVoiceButton,
}: InteractiveMainNavigatorViewProps) {
  const { width: viewportWidth } = useWindowDimensions();
  const trackX = useSharedValue(0);
  const swipeProgress = useSharedValue(0);
  const swipeFromIndex = useSharedValue(state.index);
  const swipeToIndex = useSharedValue(-1);
  const swipeInteracting = useSharedValue(0);
  const [reduceMotion, setReduceMotion] = useState(false);
  const activeIndex = state.index;

  const normalizeTrack = useCallback(() => {
    cancelAnimation(trackX);
    trackX.value = 0;
    swipeProgress.value = 0;
    swipeFromIndex.value = state.index;
    swipeToIndex.value = -1;
    swipeInteracting.value = 0;
  }, [state.index, swipeFromIndex, swipeInteracting, swipeProgress, swipeToIndex, trackX]);

  const commitRoute = useCallback((destinationIndex: number) => {
    const destination = state.routes[destinationIndex];
    if (!destination) return;
    navigation.dispatch(CommonActions.navigate({ name: destination.name, merge: true }));
    const label = BOTTOM_NAVIGATION_ITEMS.find((item) => item.id === destination.name)?.label;
    if (label) AccessibilityInfo.announceForAccessibility(label);
  }, [navigation, state.routes]);

  useEffect(normalizeTrack, [activeIndex, viewportWidth, normalizeTrack]);
  useEffect(() => {
    let mounted = true;
    AccessibilityInfo.isReduceMotionEnabled().then((enabled) => {
      if (mounted) setReduceMotion(enabled);
    });
    const motionSubscription = AccessibilityInfo.addEventListener('reduceMotionChanged', setReduceMotion);
    const appSubscription = AppState.addEventListener('change', (nextState) => {
      if (nextState !== 'active') normalizeTrack();
    });
    return () => {
      mounted = false;
      motionSubscription.remove();
      appSubscription.remove();
    };
  }, [normalizeTrack]);

  const horizontalPan = useMemo(() => Gesture.Pan()
    .enabled(!reduceMotion)
    .activeOffsetX([-18, 18])
    .failOffsetY([-14, 14])
    .cancelsTouchesInView(true)
    .onBegin(() => {
      swipeFromIndex.value = activeIndex;
      swipeToIndex.value = -1;
      swipeProgress.value = 0;
      swipeInteracting.value = 1;
    })
    .onUpdate((event) => {
      const direction = event.translationX < 0 ? 1 : event.translationX > 0 ? -1 : 0;
      const destinationIndex = activeIndex + direction;
      const edge = direction !== 0 && (destinationIndex < 0 || destinationIndex >= state.routes.length);
      trackX.value = event.translationX * (edge ? MAIN_EDGE_RESISTANCE : MAIN_SWIPE_TRACKING);
      swipeToIndex.value = edge || direction === 0 ? -1 : destinationIndex;
      swipeProgress.value = edge ? 0 : Math.min(Math.abs(trackX.value) / viewportWidth, 1);
    })
    .onEnd((event) => {
      const resolution = resolveMainSwipe({
        activeIndex,
        routeCount: state.routes.length,
        translationX: event.translationX,
        velocityX: event.velocityX,
      });
      if (resolution.kind === 'cancel') {
        trackX.value = withSpring(0, CANCEL_SPRING);
        swipeProgress.value = withSpring(0, CANCEL_SPRING, (finished) => {
          if (finished) {
            swipeToIndex.value = -1;
            swipeInteracting.value = 0;
          }
        });
        return;
      }
      trackX.value = withTiming(resolution.direction * -viewportWidth, { duration: 220 }, (finished) => {
        if (finished) runOnJS(commitRoute)(resolution.destinationIndex);
      });
      swipeProgress.value = withTiming(1, { duration: 220 });
    })
    .onFinalize((_event, success) => {
      if (!success) {
        trackX.value = withSpring(0, CANCEL_SPRING);
        swipeProgress.value = withSpring(0, CANCEL_SPRING, (finished) => {
          if (finished) {
            swipeToIndex.value = -1;
            swipeInteracting.value = 0;
          }
        });
      }
    }), [activeIndex, commitRoute, reduceMotion, state.routes.length, swipeFromIndex, swipeInteracting, swipeProgress, swipeToIndex, trackX, viewportWidth]);

  const trackStyle = useAnimatedStyle(() => ({ transform: [{ translateX: trackX.value }] }));

  return (
    <MainNavigationInteractionContext.Provider value={{
      progress: swipeProgress,
      fromIndex: swipeFromIndex,
      toIndex: swipeToIndex,
      interacting: swipeInteracting,
    }}>
    <View className="flex-1" testID="main-navigation-shell">
      <GestureDetector gesture={horizontalPan}>
        <View collapsable={false} className="flex-1 overflow-hidden bg-white" testID="main-scene-viewport">
          <Animated.View testID="main-scene-track" style={[{ position: 'absolute', inset: 0 }, trackStyle]}>
            {state.routes.map((route, routeIndex) => (
              <View
                key={route.key}
                testID={`main-scene-${route.name}`}
                pointerEvents={routeIndex === activeIndex ? 'auto' : 'none'}
                style={{
                  position: 'absolute', top: 0, bottom: 0, width: viewportWidth,
                  left: (routeIndex - activeIndex) * viewportWidth,
                }}
              >
                {descriptors[route.key].render()}
              </View>
            ))}
          </Animated.View>
        </View>
      </GestureDetector>
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

import { useEffect } from 'react';
import { useWindowDimensions, View } from 'react-native';
import { router, Tabs, usePathname } from 'expo-router';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import Animated, { cancelAnimation, runOnJS, useSharedValue, useAnimatedStyle, withSpring, withTiming, interpolate } from 'react-native-reanimated';
import { BottomNavBar } from '../../src/components/ui/BottomNavBar';
import { VoiceButton } from '../../src/components/VoiceButton';
import { ScrollProvider } from '../../src/contexts/ScrollContext';
import { useUIStore } from '../../src/stores/uiStore';
import { CURRENT_INITIAL_TAB } from '../../src/navigation/currentExperience';
import {
  BOTTOM_NAVIGATION_ITEMS,
  getAdjacentBottomNavigationDestination,
  getBottomNavigationPageTransition,
  type BottomNavigationItem,
} from '../../src/navigation/bottomNavigation';
import { getTabSurfaceChatTransition } from '../../src/navigation/chatCardExpansion';

const SCALE_BACK = { damping: 30, stiffness: 250 };
const PAGE_TRANSITION = getBottomNavigationPageTransition();

export default function TabLayout() {
  const pathname = usePathname();
  const { width: viewportWidth } = useWindowDimensions();
  const { chatMorphing } = useUIStore();
  const chatProgress = useSharedValue(0);
  const pageTranslateX = useSharedValue(0);
  const activeDestination = BOTTOM_NAVIGATION_ITEMS.find((item) => (
    item.path === '/' ? pathname === '/' || pathname === '/index' : pathname.startsWith(item.path)
  ))?.id ?? 'index';
  const leftDestination = getAdjacentBottomNavigationDestination(activeDestination, 'left');
  const rightDestination = getAdjacentBottomNavigationDestination(activeDestination, 'right');

  function navigateBySwipe(destination: BottomNavigationItem['id']) {
    const item = BOTTOM_NAVIGATION_ITEMS.find((candidate) => candidate.id === destination);
    if (item) router.navigate(item.path as never);
  }

  const pageSwipeGesture = Gesture.Pan()
    .activeOffsetX([-18, 18])
    .failOffsetY([-14, 14])
    .onUpdate((event) => {
      const destination = event.translationX < 0 ? leftDestination : rightDestination;
      pageTranslateX.value = destination === null
        ? event.translationX * 0.18
        : event.translationX;
    })
    .onEnd((event) => {
      const direction = event.translationX < 0 ? 'left' : 'right';
      const destination = direction === 'left' ? leftDestination : rightDestination;
      const commits = destination !== null
        && (Math.abs(event.translationX) > 72 || Math.abs(event.velocityX) > 700);
      if (!commits || destination === null) {
        pageTranslateX.value = withSpring(0, { damping: 28, stiffness: 320, overshootClamping: true });
        return;
      }
      const exitX = direction === 'left' ? -viewportWidth : viewportWidth;
      pageTranslateX.value = withTiming(exitX, { duration: 180 }, (finished) => {
        if (!finished) return;
        pageTranslateX.value = 0;
        runOnJS(navigateBySwipe)(destination);
      });
    });

  useEffect(() => {
    const transition = getTabSurfaceChatTransition(chatMorphing);
    if (transition === 'spring-open') {
      chatProgress.value = withSpring(1, SCALE_BACK);
      return;
    }

    cancelAnimation(chatProgress);
    chatProgress.value = 0;
  }, [chatMorphing]);

  // Tabs content scales back and gets rounded corners as the chat sheet rises —
  // matching the iOS native sheet presentation feel.
  const scaleStyle = useAnimatedStyle(() => ({
    flex: 1,
    backgroundColor: PAGE_TRANSITION.backdropColor,
    borderRadius: interpolate(chatProgress.value, [0, 1], [0, 28]),
    transform: [
      { translateX: pageTranslateX.value },
      { scale: interpolate(chatProgress.value, [0, 1], [1, 0.92]) },
    ],
    overflow: 'hidden',
  }));

  return (
    <ScrollProvider>
      {/* Dark backdrop shows around the scaled-back tabs content. */}
      <View style={{ flex: 1, backgroundColor: '#111111' }}>
        <GestureDetector gesture={pageSwipeGesture}>
        <Animated.View collapsable={false} style={scaleStyle}>
          <Tabs
            initialRouteName={CURRENT_INITIAL_TAB}
            screenOptions={{
              headerShown: false,
              tabBarStyle: { display: 'none' },
              animation: PAGE_TRANSITION.sceneAnimation,
            }}
          >
            <Tabs.Screen name="index" />
            <Tabs.Screen name="chats" />
            <Tabs.Screen name="you" />
          </Tabs>
          <BottomNavBar />
          <VoiceButton />
        </Animated.View>
        </GestureDetector>
      </View>
    </ScrollProvider>
  );
}

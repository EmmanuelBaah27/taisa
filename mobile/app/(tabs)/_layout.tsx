import { useEffect } from 'react';
import { View } from 'react-native';
import Animated, { cancelAnimation, useSharedValue, useAnimatedStyle, withSpring, interpolate } from 'react-native-reanimated';
import { ScrollProvider } from '../../src/contexts/ScrollContext';
import { useUIStore } from '../../src/stores/uiStore';
import { CURRENT_INITIAL_TAB } from '../../src/navigation/currentExperience';
import { getBottomNavigationPageTransition } from '../../src/navigation/bottomNavigation';
import { getTabSurfaceChatTransition } from '../../src/navigation/chatCardExpansion';
import { InteractiveMainNavigator } from '../../src/navigation/InteractiveMainNavigator';

const SCALE_BACK = { damping: 30, stiffness: 250 };
const PAGE_TRANSITION = getBottomNavigationPageTransition();

export default function TabLayout() {
  const { chatMorphing } = useUIStore();
  const chatProgress = useSharedValue(0);

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
      { scale: interpolate(chatProgress.value, [0, 1], [1, 0.92]) },
    ],
    overflow: 'hidden',
  }));

  return (
    <ScrollProvider>
      {/* Dark backdrop shows around the scaled-back tabs content. */}
      <View style={{ flex: 1, backgroundColor: '#111111' }}>
        <Animated.View collapsable={false} style={scaleStyle}>
          <InteractiveMainNavigator initialRouteName={CURRENT_INITIAL_TAB}>
            <InteractiveMainNavigator.Screen name="chats" />
            <InteractiveMainNavigator.Screen name="index" />
            <InteractiveMainNavigator.Screen name="you" />
          </InteractiveMainNavigator>
        </Animated.View>
      </View>
    </ScrollProvider>
  );
}

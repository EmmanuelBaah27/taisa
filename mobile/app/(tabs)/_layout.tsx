import { useEffect } from 'react';
import { View } from 'react-native';
import { Tabs } from 'expo-router';
import Animated, { useSharedValue, useAnimatedStyle, withSpring, interpolate } from 'react-native-reanimated';
import { BottomNavBar } from '../../src/components/ui/BottomNavBar';
import { VoiceButton } from '../../src/components/VoiceButton';
import { ScrollProvider } from '../../src/contexts/ScrollContext';
import { useUIStore } from '../../src/stores/uiStore';
import { CURRENT_INITIAL_TAB } from '../../src/navigation/currentExperience';

const SCALE_BACK = { damping: 30, stiffness: 250 };

export default function TabLayout() {
  const { chatMorphing } = useUIStore();
  const chatProgress = useSharedValue(0);

  useEffect(() => {
    chatProgress.value = withSpring(chatMorphing ? 1 : 0, SCALE_BACK);
  }, [chatMorphing]);

  // Tabs content scales back and gets rounded corners as the chat sheet rises —
  // matching the iOS native sheet presentation feel.
  const scaleStyle = useAnimatedStyle(() => ({
    flex: 1,
    borderRadius: interpolate(chatProgress.value, [0, 1], [0, 28]),
    transform: [{ scale: interpolate(chatProgress.value, [0, 1], [1, 0.92]) }],
    overflow: 'hidden',
  }));

  return (
    <ScrollProvider>
      {/* Dark backdrop shows around the scaled-back tabs content. */}
      <View style={{ flex: 1, backgroundColor: '#111111' }}>
        <Animated.View style={scaleStyle}>
          <Tabs
            initialRouteName={CURRENT_INITIAL_TAB}
            screenOptions={{
              headerShown: false,
              tabBarStyle: { display: 'none' },
            }}
          >
            <Tabs.Screen name="index" />
            <Tabs.Screen name="insights" />
            <Tabs.Screen name="goals" />
            <Tabs.Screen name="logs" />
            <Tabs.Screen name="you" />
          </Tabs>
          <BottomNavBar />
          <VoiceButton />
        </Animated.View>
      </View>
    </ScrollProvider>
  );
}

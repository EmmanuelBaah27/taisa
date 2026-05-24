import { useEffect } from 'react';
import { View } from 'react-native';
import { Tabs } from 'expo-router';
import Animated, { useSharedValue, useAnimatedStyle, withSpring, interpolate } from 'react-native-reanimated';
import { TopNavBar } from '../../src/components/ui/TopNavBar';
import { VoiceButton } from '../../src/components/VoiceButton';
import { ScrollProvider } from '../../src/contexts/ScrollContext';
import { useUIStore } from '../../src/stores/uiStore';
import ChatScreen from '../chat/index';

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
          <TopNavBar />
          <Tabs
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
          <VoiceButton />
        </Animated.View>

        {/* Chat sheet — rendered outside the scaled wrapper so it isn't affected. */}
        {chatMorphing && (
          <View style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, zIndex: 100 }}>
            <ChatScreen />
          </View>
        )}
      </View>
    </ScrollProvider>
  );
}

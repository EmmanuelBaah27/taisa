import { useEffect } from 'react';
import { View } from 'react-native';
import { Tabs } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { TopNavBar } from '../../src/components/ui/TopNavBar';
import { VoiceButton } from '../../src/components/VoiceButton';
import { ScrollProvider } from '../../src/contexts/ScrollContext';
import { useUIStore } from '../../src/stores/uiStore';
import ChatScreen from '../chat/index';

export default function TabLayout() {
  const { chatMorphing, setPillBottomInset } = useUIStore();
  const insets = useSafeAreaInsets();

  useEffect(() => {
    setPillBottomInset(insets.bottom + 16);
  }, [insets.bottom]);

  return (
    <ScrollProvider>
      <View style={{ flex: 1, backgroundColor: '#ffffff', overflow: 'visible' }}>
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
        {/* Chat sits above all tab content — mounted here so navigation state never changes. */}
        {chatMorphing && (
          <View style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, zIndex: 100 }}>
            <ChatScreen />
          </View>
        )}
      </View>
    </ScrollProvider>
  );
}

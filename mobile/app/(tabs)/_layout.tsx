import { View } from 'react-native';
import { Tabs } from 'expo-router';
import { TopNavBar } from '../../src/components/ui/TopNavBar';
import { VoiceButton } from '../../src/components/VoiceButton';

export default function TabLayout() {
  return (
    <View style={{ flex: 1, backgroundColor: '#ffffff' }}>
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
    </View>
  );
}

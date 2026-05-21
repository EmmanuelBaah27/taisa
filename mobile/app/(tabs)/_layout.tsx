import { useEffect } from 'react';
import { View } from 'react-native';
import { Tabs, usePathname } from 'expo-router';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withTiming,
} from 'react-native-reanimated';
import { TopNavBar } from '../../src/components/ui/TopNavBar';
import { VoiceButton } from '../../src/components/VoiceButton';
import { ScrollProvider } from '../../src/contexts/ScrollContext';

const TAB_PATHS = new Set(['/', '/index', '/insights', '/goals', '/logs', '/you']);

export default function TabLayout() {
  const pathname = usePathname();

  const opacity = useSharedValue(1);

  useEffect(() => {
    if (!TAB_PATHS.has(pathname)) return;
    opacity.value = 0;
    opacity.value = withTiming(1, { duration: 180 });
  }, [pathname]);

  const contentStyle = useAnimatedStyle(() => ({
    flex: 1,
    opacity: opacity.value,
  }));

  return (
    <ScrollProvider>
      <View style={{ flex: 1, backgroundColor: '#ffffff', overflow: 'visible' }}>
        <TopNavBar />
        <Animated.View style={contentStyle}>
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
        </Animated.View>
        <VoiceButton />
      </View>
    </ScrollProvider>
  );
}

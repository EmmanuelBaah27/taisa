import '../global.css';
import { useEffect } from 'react';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useFonts } from 'expo-font';
import * as SplashScreen from 'expo-splash-screen';
import * as SecureStore from 'expo-secure-store';
import { useCareerStore } from '../src/stores/careerStore';

SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  const { fetchProfile } = useCareerStore();

  const [fontsLoaded] = useFonts({
    'StrichpunktSans': require('../assets/fonts/StrichpunktSans-Regular.ttf'),
    'StrichpunktSans-Medium': require('../assets/fonts/StrichpunktSans-Medium.ttf'),
    'StrichpunktSans-Bold': require('../assets/fonts/StrichpunktSans-Bold.ttf'),
  });

  useEffect(() => {
    if (fontsLoaded) SplashScreen.hideAsync();
  }, [fontsLoaded]);

  useEffect(() => {
    async function hydrateUser() {
      const userId = await SecureStore.getItemAsync('userId');
      if (userId) {
        try {
          await fetchProfile();
        } catch (e) {
          // Profile fetch failed — user will see onboarding
        }
      }
    }
    hydrateUser();
  }, []);

  if (!fontsLoaded) return null;

  return (
    <>
      <StatusBar style="dark" />
      <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: '#ffffff' } }}>
        <Stack.Screen name="(tabs)" />
        <Stack.Screen name="onboarding/index" />
        <Stack.Screen name="thread/[id]" />
        <Stack.Screen
          name="recording/index"
          options={{ presentation: 'transparentModal', animation: 'slide_from_bottom' }}
        />
      </Stack>
    </>
  );
}

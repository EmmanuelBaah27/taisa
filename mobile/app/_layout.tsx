import '../global.css';
import { useEffect } from 'react';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import * as SecureStore from 'expo-secure-store';
import { useCareerStore } from '../src/stores/careerStore';

export default function RootLayout() {
  const { fetchProfile } = useCareerStore();

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

  return (
    <>
      <StatusBar style="light" />
      <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: '#0A0A0F' } }}>
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

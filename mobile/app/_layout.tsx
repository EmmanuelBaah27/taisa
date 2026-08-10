import '../global.css';
import { useEffect, useState } from 'react';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { AppState, Text, TouchableOpacity, View } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { useFonts } from 'expo-font';
import * as SplashScreen from 'expo-splash-screen';
import * as SecureStore from 'expo-secure-store';
import { useCareerStore } from '../src/stores/careerStore';
import {
  getPrivacyGuard,
  type GuardedAppState,
} from '../src/services/privacyGuard';

SplashScreen.preventAutoHideAsync();

function makeDeviceId(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  });
}

export default function RootLayout() {
  const { initUser, fetchProfile } = useCareerStore();
  const privacyGuard = getPrivacyGuard();
  const [privacyState, setPrivacyState] = useState(privacyGuard.getState());

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
        } catch {
          // Profile gone — re-init with same id
          await initUser(userId, {});
        }
      } else {
        await initUser(makeDeviceId(), {});
      }
    }
    hydrateUser();
  }, []);

  useEffect(() => {
    const unsubscribe = privacyGuard.subscribe(setPrivacyState);
    let mounted = true;
    const normalizeAppState = (value: string): GuardedAppState => (
      value === 'active' || value === 'background' ? value : 'inactive'
    );
    const initialize = async () => {
      const initialized = await privacyGuard.initialize();
      if (!mounted) return;
      const current = normalizeAppState(AppState.currentState);
      privacyGuard.handleAppState(current);
      if (current === 'active' && initialized.lockEnabled) {
        await privacyGuard.unlock();
      }
    };
    void initialize().catch(() => {
      // The guard remains fail-closed and shielded when its SecureStore preference is unreadable.
    });
    const subscription = AppState.addEventListener('change', (nextState) => {
      const normalized = normalizeAppState(nextState);
      const next = privacyGuard.handleAppState(normalized);
      if (normalized === 'active' && next.lockEnabled) void privacyGuard.unlock();
    });
    return () => {
      mounted = false;
      subscription.remove();
      unsubscribe();
    };
  }, [privacyGuard]);

  if (!fontsLoaded) return null;

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <StatusBar style="dark" />
      <Stack screenOptions={{ headerShown: false, animation: 'none', contentStyle: { backgroundColor: '#ffffff' } }}>
        <Stack.Screen name="(tabs)" />
        <Stack.Screen name="onboarding/index" />
        <Stack.Screen name="thread/[id]" />
        <Stack.Screen
          name="recording/index"
          options={{ presentation: 'transparentModal', animation: 'slide_from_bottom' }}
        />
        <Stack.Screen name="chat/index" />
      </Stack>
      {privacyState.shielded ? (
        <View
          className="absolute inset-0 items-center justify-center bg-background px-8"
          style={{ zIndex: 9999 }}
          accessibilityViewIsModal
        >
          <Text className="text-foreground text-xl font-bold">Taisa is private</Text>
          <Text className="text-text-tertiary text-sm text-center mt-2">
            {privacyState.appState === 'active'
              ? 'Unlock to view your career archive.'
              : 'Your career archive is hidden.'}
          </Text>
          {privacyState.appState === 'active' && privacyState.lockEnabled ? (
            <TouchableOpacity
              className="bg-primary rounded-full px-6 py-3 mt-5"
              disabled={privacyState.phase === 'unlocking'}
              onPress={() => { void privacyGuard.unlock(); }}
            >
              <Text className="text-foreground text-sm font-semibold">
                {privacyState.phase === 'unlocking' ? 'Unlocking…' : 'Unlock Taisa'}
              </Text>
            </TouchableOpacity>
          ) : null}
        </View>
      ) : null}
    </GestureHandlerRootView>
  );
}

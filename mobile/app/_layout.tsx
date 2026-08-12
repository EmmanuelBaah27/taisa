import '../global.css';
import { useEffect, useState } from 'react';
import { router, Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { AppState, Text, TouchableOpacity, View } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { useFonts } from 'expo-font';
import * as SplashScreen from 'expo-splash-screen';
import { useCareerStore } from '../src/stores/careerStore';
import {
  getPrivacyGuard,
  type GuardedAppState,
} from '../src/services/privacyGuard';
import {
  hydrateStartupProfile,
  recoveryPresentation,
  type StartupProfileResult,
} from '../src/services/startupProfile';

SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  const { fetchProfile } = useCareerStore();
  const privacyGuard = getPrivacyGuard();
  const [privacyState, setPrivacyState] = useState(privacyGuard.getState());
  const [startup, setStartup] = useState<StartupProfileResult | null>(null);

  const [fontsLoaded] = useFonts({
    'StrichpunktSans': require('../assets/fonts/StrichpunktSans-Regular.ttf'),
    'StrichpunktSans-Medium': require('../assets/fonts/StrichpunktSans-Medium.ttf'),
    'StrichpunktSans-Bold': require('../assets/fonts/StrichpunktSans-Bold.ttf'),
  });

  useEffect(() => {
    if (fontsLoaded) SplashScreen.hideAsync();
  }, [fontsLoaded]);

  useEffect(() => {
    void hydrateStartupProfile({
      fetchProfile,
      route: () => router.replace('/onboarding'),
    }).then(setStartup).catch(() => {
      // Unknown failures remain fail-closed instead of exposing readable screens.
      setStartup(null);
    });
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

  if (!fontsLoaded || startup === null) return null;

  if (startup.status === 'recovery-required') {
    const presentation = recoveryPresentation(startup.error);
    return (
      <View className="flex-1 items-center justify-center bg-background px-8">
        <Text className="text-foreground text-xl font-bold text-center">{presentation.title}</Text>
        <Text className="text-text-tertiary text-sm text-center mt-3">{presentation.body}</Text>
        <TouchableOpacity
          className="bg-primary rounded-full px-6 py-3 mt-6"
          onPress={() => {
            setStartup(null);
            void hydrateStartupProfile({
              fetchProfile,
              route: () => router.replace('/onboarding'),
            }).then(setStartup).catch(() => { setStartup(null); });
          }}
        >
          <Text className="text-foreground text-sm font-semibold">Retry securely</Text>
        </TouchableOpacity>
      </View>
    );
  }

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

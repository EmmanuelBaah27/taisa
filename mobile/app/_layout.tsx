import '../global.css';
import { useEffect, useState } from 'react';
import { router, Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { AppState, View } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { useFonts } from 'expo-font';
import { Inter_400Regular } from '@expo-google-fonts/inter/400Regular';
import { Inter_500Medium } from '@expo-google-fonts/inter/500Medium';
import { Inter_600SemiBold } from '@expo-google-fonts/inter/600SemiBold';
import { Inter_700Bold } from '@expo-google-fonts/inter/700Bold';
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
import { CURRENT_INITIAL_STACK } from '../src/navigation/currentExperience';
import { LiquidGlassPressable } from '../src/components/ui/LiquidGlassPressable';
import { Text } from '../src/components/ui/Text';
import { colorTokens } from '../src/design-system/tokens';

SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  const { fetchProfile } = useCareerStore();
  const privacyGuard = getPrivacyGuard();
  const [privacyState, setPrivacyState] = useState(privacyGuard.getState());
  const [startup, setStartup] = useState<StartupProfileResult | null>(null);

  const [fontsLoaded] = useFonts({
    Inter_400Regular,
    Inter_500Medium,
    Inter_600SemiBold,
    Inter_700Bold,
  });

  useEffect(() => {
    if (fontsLoaded && startup !== null && privacyState.initialized) {
      void SplashScreen.hideAsync();
    }
  }, [fontsLoaded, privacyState.initialized, startup]);

  useEffect(() => {
    void hydrateStartupProfile({
      fetchProfile,
    }).then(setStartup).catch(() => {
      // Unknown failures remain fail-closed instead of exposing readable screens.
      setStartup(null);
    });
  }, []);

  useEffect(() => {
    if (startup?.status === 'onboarding') router.replace('/onboarding');
  }, [startup]);

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
      if (normalized === 'active' && next.lockEnabled && next.phase === 'locked') {
        void privacyGuard.unlock();
      }
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
        <Text role="subheading" align="center">{presentation.title}</Text>
        <View className="mt-3"><Text role="label" color="tertiary" align="center">{presentation.body}</Text></View>
        <LiquidGlassPressable
          accessibilityLabel="Retry secure recovery"
          hierarchy="prominent"
          tone="accent"
          className="mt-6 px-6 py-3"
          onPress={() => {
            setStartup(null);
            void hydrateStartupProfile({
              fetchProfile,
            }).then(setStartup).catch(() => { setStartup(null); });
          }}
        >
          <Text role="labelStrong">Retry securely</Text>
        </LiquidGlassPressable>
      </View>
    );
  }

  return (
    <GestureHandlerRootView style={{ flex: 1, backgroundColor: colorTokens.surface.app }}>
      <StatusBar style="dark" />
      <Stack initialRouteName={CURRENT_INITIAL_STACK} screenOptions={{ headerShown: false, animation: 'none', contentStyle: { backgroundColor: colorTokens.surface.app } }}>
        <Stack.Screen name="(tabs)" />
        <Stack.Screen name="onboarding/index" />
        <Stack.Screen name="thread/[id]" />
        <Stack.Screen name="recording/index" />
        <Stack.Screen
          name="chat/index"
          options={{
            presentation: 'transparentModal',
            animation: 'none',
            contentStyle: { backgroundColor: 'transparent' },
          }}
        />
      </Stack>
      {privacyState.shielded ? (
        <View
          className="absolute inset-0 items-center justify-center bg-background px-8"
          style={{ zIndex: 9999, backgroundColor: colorTokens.surface.app }}
          accessibilityViewIsModal
        >
          <Text role="subheading" align="center">Taisa is private</Text>
          <View className="mt-2"><Text role="label" color="tertiary" align="center">
            {privacyState.appState === 'active'
              ? 'Unlock to view your career archive.'
              : 'Your career archive is hidden.'}
          </Text></View>
          {privacyState.appState === 'active' && privacyState.lockEnabled ? (
            <LiquidGlassPressable
              accessibilityLabel="Unlock Taisa"
              hierarchy="prominent"
              tone="accent"
              className="mt-5 px-6 py-3"
              disabled={privacyState.phase === 'unlocking'}
              onPress={() => { void privacyGuard.unlock(); }}
            >
              <Text role="labelStrong">
                {privacyState.phase === 'unlocking' ? 'Unlocking…' : 'Unlock Taisa'}
              </Text>
            </LiquidGlassPressable>
          ) : null}
        </View>
      ) : null}
    </GestureHandlerRootView>
  );
}

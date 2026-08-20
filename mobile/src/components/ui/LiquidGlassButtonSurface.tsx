import { BlurView } from 'expo-blur';
import { LinearGradient } from 'expo-linear-gradient';
import { useEffect, useState, type ReactNode } from 'react';
import {
  AccessibilityInfo,
  Platform,
  type StyleProp,
  type ViewStyle,
} from 'react-native';
import Animated, {
  useAnimatedStyle,
  type SharedValue,
} from 'react-native-reanimated';

import {
  getLiquidGlassAppearance,
  resolveLiquidGlassMode,
  resolveOptionalLiquidGlassModule,
  type LiquidGlassHierarchy,
  type LiquidGlassShape,
  type LiquidGlassTone,
} from './liquidGlass';

const nativeGlassEnabled = Platform.OS === 'ios'
  && process.env.NODE_ENV !== 'test'
  && process.env.EXPO_PUBLIC_NATIVE_GLASS_ENABLED !== 'false';
const glassEffectModule = resolveOptionalLiquidGlassModule(
  nativeGlassEnabled,
  () => require('expo-glass-effect') as typeof import('expo-glass-effect'),
);
const NativeGlassView = glassEffectModule?.GlassView;

export interface LiquidGlassButtonSurfaceProps {
  hierarchy: LiquidGlassHierarchy;
  tone: LiquidGlassTone;
  shape: LiquidGlassShape;
  disabled?: boolean;
  pressed?: SharedValue<number>;
  children?: ReactNode;
  style?: StyleProp<ViewStyle>;
  testID?: string;
}

export function getLiquidGlassShapeStyle(shape: LiquidGlassShape): ViewStyle {
  if (shape === 'rounded') return { borderRadius: 16 };
  if (shape === 'circle') return { borderRadius: 9999, aspectRatio: 1 };
  return { borderRadius: 9999 };
}

export function getLiquidGlassPressScale(
  pressed: number,
  reduceMotion: boolean,
  disabled: boolean,
): number {
  'worklet';
  if (reduceMotion || disabled) return 1;
  return 1 - (0.03 * Math.max(0, Math.min(1, pressed)));
}

function useAccessibilityPreferences() {
  const [reduceTransparency, setReduceTransparency] = useState(false);
  const [reduceMotion, setReduceMotion] = useState(false);

  useEffect(() => {
    let mounted = true;
    AccessibilityInfo.isReduceTransparencyEnabled().then((value) => {
      if (mounted) setReduceTransparency(value);
    });
    AccessibilityInfo.isReduceMotionEnabled().then((value) => {
      if (mounted) setReduceMotion(value);
    });
    const transparencySubscription = AccessibilityInfo.addEventListener(
      'reduceTransparencyChanged',
      setReduceTransparency,
    );
    const motionSubscription = AccessibilityInfo.addEventListener(
      'reduceMotionChanged',
      setReduceMotion,
    );

    return () => {
      mounted = false;
      transparencySubscription.remove();
      motionSubscription.remove();
    };
  }, []);

  return { reduceTransparency, reduceMotion };
}

export function LiquidGlassButtonSurface({
  hierarchy,
  tone,
  shape,
  disabled = false,
  pressed,
  children,
  style,
  testID,
}: LiquidGlassButtonSurfaceProps) {
  const { reduceTransparency, reduceMotion } = useAccessibilityPreferences();
  const appearance = getLiquidGlassAppearance(hierarchy, tone);
  const apiAvailable = glassEffectModule
    ? (() => {
        try {
          return glassEffectModule.isGlassEffectAPIAvailable();
        } catch {
          return false;
        }
      })()
    : false;
  const liquidGlassAvailable = glassEffectModule
    ? (() => {
        try {
          return glassEffectModule.isLiquidGlassAvailable();
        } catch {
          return false;
        }
      })()
    : false;
  const mode = resolveLiquidGlassMode({
    platform: Platform.OS,
    nativeEnabled: nativeGlassEnabled,
    apiAvailable,
    liquidGlassAvailable,
    reduceTransparency,
  });
  const shapeStyle = getLiquidGlassShapeStyle(shape);
  const fallbackAnimatedStyle = useAnimatedStyle(() => ({
    transform: [{
      scale: getLiquidGlassPressScale(pressed?.value ?? 0, reduceMotion, disabled),
    }],
  }));

  if (mode === 'native' && NativeGlassView) {
    return (
      <NativeGlassView
        key="native-interactive"
        testID={testID ?? 'liquid-glass-native'}
        isInteractive
        glassEffectStyle={appearance.glassEffectStyle}
        tintColor={appearance.tintColor}
        colorScheme="light"
        style={[shapeStyle, { overflow: 'hidden' }, style]}
      >
        {children}
      </NativeGlassView>
    );
  }

  return (
    <Animated.View
      key="fallback"
      testID={testID ?? 'liquid-glass-fallback'}
      style={[
        shapeStyle,
        {
          overflow: 'hidden',
          borderWidth: 1,
          borderColor: appearance.fallback.borderColor,
          backgroundColor: appearance.fallback.backgroundColor,
          shadowColor: appearance.fallback.shadowColor,
          shadowOffset: { width: 0, height: 2 },
          shadowOpacity: appearance.fallback.shadowOpacity,
          shadowRadius: hierarchy === 'prominent' ? 12 : 7,
        },
        style,
        fallbackAnimatedStyle,
      ]}
    >
      <BlurView
        pointerEvents="none"
        intensity={appearance.fallback.blurIntensity}
        tint="systemThinMaterialLight"
        style={{ position: 'absolute', inset: 0 }}
      />
      <LinearGradient
        pointerEvents="none"
        colors={[...appearance.fallback.sheenColors]}
        start={{ x: 0.15, y: 0 }}
        end={{ x: 0.85, y: 1 }}
        style={{ position: 'absolute', inset: 0 }}
      />
      {children}
    </Animated.View>
  );
}

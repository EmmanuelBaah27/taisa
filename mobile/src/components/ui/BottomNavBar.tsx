import { BlurView } from 'expo-blur';
import { LinearGradient } from 'expo-linear-gradient';
import { router, usePathname } from 'expo-router';
import { type ReactNode } from 'react';
import { Platform, Pressable, View, type ViewStyle } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Animated, {
  Extrapolation,
  interpolate,
  useAnimatedStyle,
  useDerivedValue,
  useSharedValue,
  withSpring,
  type SharedValue,
} from 'react-native-reanimated';

import {
  BOTTOM_NAVIGATION_FIGMA,
  BOTTOM_NAVIGATION_FALLBACK_GLASS,
  BOTTOM_NAVIGATION_ITEMS,
  BOTTOM_NAVIGATION_LABEL_WIDTHS,
  getBottomNavigationLayout,
  resolveGlassAvailability,
  resolveOptionalGlassModule,
  type BottomNavigationItem,
} from '../../navigation/bottomNavigation';
import {
  navigateWithMainNavigation,
  useMainNavigationInteraction,
} from '../../navigation/MainNavigationInteractionContext';
import { useCareerStore } from '../../stores/careerStore';
import { Icon } from './Icon';
import { NaviiAvatar } from './NaviiAvatar';

const nativeGlassEnabled = process.env.EXPO_PUBLIC_NATIVE_GLASS_ENABLED !== 'false';
const glassEffectModule = resolveOptionalGlassModule(
  nativeGlassEnabled,
  () => require('expo-glass-effect') as typeof import('expo-glass-effect'),
);
const NativeGlassView = glassEffectModule?.GlassView;
const supportsNativeGlass = Platform.OS === 'ios'
  && glassEffectModule !== null
  && resolveGlassAvailability(
    glassEffectModule.isGlassEffectAPIAvailable,
    glassEffectModule.isLiquidGlassAvailable,
  );

const materialStyle: ViewStyle = {
  width: '100%', height: 60, overflow: 'hidden', borderRadius: 32,
  borderWidth: 1, borderColor: BOTTOM_NAVIGATION_FALLBACK_GLASS.borderColor,
};
const SHELL_WIDTHS = [240, 240, 220] as const;
const ITEM_X = [
  [6, 118, 178],
  [6, 66, 178],
  [6, 66, 126],
] as const;
const ITEM_WIDTHS = [
  [108, 56, 56],
  [56, 108, 56],
  [56, 56, 88],
] as const;
const CAPSULE_X = [6, 66, 126] as const;
const CAPSULE_WIDTH = [108, 108, 88] as const;
const CAPSULE_OPTICAL_OFFSET_Y = 2;
const PRESS_SPRING = { damping: 24, stiffness: 360, mass: 0.7 } as const;

function NavigationMaterial({ children }: { children: ReactNode }) {
  if (supportsNativeGlass && NativeGlassView) {
    return (
      <NativeGlassView
        isInteractive
        glassEffectStyle="regular"
        tintColor="rgba(255,255,255,0.10)"
        colorScheme="light"
        style={materialStyle}
      >
        {children}
      </NativeGlassView>
    );
  }
  return (
    <BlurView
      intensity={BOTTOM_NAVIGATION_FALLBACK_GLASS.intensity}
      tint={BOTTOM_NAVIGATION_FALLBACK_GLASS.tint}
      style={materialStyle}
    >
      <LinearGradient
        pointerEvents="none"
        colors={[...BOTTOM_NAVIGATION_FALLBACK_GLASS.sheenColors]}
        start={{ x: 0.15, y: 0 }}
        end={{ x: 0.85, y: 1 }}
        style={{ position: 'absolute', inset: 0 }}
      />
      {children}
    </BlurView>
  );
}

function LeadingVisual({ item, selected, userId }: {
  item: BottomNavigationItem;
  selected: boolean;
  userId: string | null;
}) {
  if (item.id === 'you' && userId) {
    return (
      <View className="h-6 w-6 items-center justify-center overflow-hidden rounded-full">
        <NaviiAvatar seed={userId} size={32} />
      </View>
    );
  }
  return (
    <Icon
      name={item.icon}
      size={24}
      color={selected ? '#0F1010' : BOTTOM_NAVIGATION_FIGMA.inactiveItem.iconColor}
    />
  );
}

function SmoothDestination({ item, index, pagePosition, userId, onPress, onPressIn, onPressOut }: {
  item: BottomNavigationItem;
  index: number;
  pagePosition: SharedValue<number>;
  userId: string | null;
  onPress: () => void;
  onPressIn: () => void;
  onPressOut: () => void;
}) {
  const frameStyle = useAnimatedStyle(() => {
    const left = interpolate(pagePosition.value, [0, 1, 2], [
      ITEM_X[0][index], ITEM_X[1][index], ITEM_X[2][index],
    ], Extrapolation.CLAMP);
    const width = interpolate(pagePosition.value, [0, 1, 2], [
      ITEM_WIDTHS[0][index], ITEM_WIDTHS[1][index], ITEM_WIDTHS[2][index],
    ], Extrapolation.CLAMP);
    return { left, width };
  });
  const selection = useDerivedValue(() => Math.max(0, 1 - Math.abs(pagePosition.value - index)));
  const contentStyle = useAnimatedStyle(() => {
    const width = interpolate(selection.value, [0, 1], [24, ITEM_WIDTHS[index][index] - 32]);
    return { width, transform: [{ translateX: interpolate(selection.value, [0, 1], [0, -4]) }] };
  });
  const selectedIconStyle = useAnimatedStyle(() => ({ opacity: selection.value }));
  const inactiveIconStyle = useAnimatedStyle(() => ({ opacity: 1 - selection.value }));
  const labelStyle = useAnimatedStyle(() => ({
    opacity: selection.value,
    transform: [
      { translateX: interpolate(selection.value, [0, 1], [-8, 0]) },
      { scale: interpolate(selection.value, [0, 1], [0.92, 1]) },
    ],
  }));

  return (
    <Animated.View
      style={[{
        position: 'absolute', top: 6 + CAPSULE_OPTICAL_OFFSET_Y, height: 48,
      }, frameStyle]}
    >
      <Pressable
        accessibilityLabel={item.label}
        accessibilityRole="tab"
        hitSlop={4}
        onPress={onPress}
        onPressIn={onPressIn}
        onPressOut={onPressOut}
        style={{ width: '100%', height: 48, alignItems: 'center', justifyContent: 'center' }}
      />
      <Animated.View
        pointerEvents="none"
        style={[{
          position: 'absolute', left: 16, top: 12, height: 24,
          flexDirection: 'row', alignItems: 'center', gap: 8, overflow: 'visible',
        }, contentStyle]}
      >
        <View style={{ width: 24, height: 24 }}>
          <Animated.View style={[{ position: 'absolute', inset: 0 }, inactiveIconStyle]}>
            <LeadingVisual item={item} selected={false} userId={userId} />
          </Animated.View>
          <Animated.View style={[{ position: 'absolute', inset: 0 }, selectedIconStyle]}>
            <LeadingVisual item={item} selected userId={userId} />
          </Animated.View>
        </View>
        <Animated.Text
          numberOfLines={1}
          className="font-sans-medium text-foreground"
          style={[{
            width: BOTTOM_NAVIGATION_LABEL_WIDTHS[item.id],
            fontSize: BOTTOM_NAVIGATION_FIGMA.selectedItem.fontSize,
            lineHeight: BOTTOM_NAVIGATION_FIGMA.selectedItem.lineHeight,
            letterSpacing: BOTTOM_NAVIGATION_FIGMA.selectedItem.letterSpacing,
          }, labelStyle]}
        >
          {item.label}
        </Animated.Text>
      </Animated.View>
    </Animated.View>
  );
}

export function BottomNavBar() {
  const interaction = useMainNavigationInteraction();
  const pathname = usePathname();
  const insets = useSafeAreaInsets();
  const userId = useCareerStore((state) => state.userId);
  const pressed = useSharedValue(0);
  const fallbackIndex = Math.max(0, BOTTOM_NAVIGATION_ITEMS.findIndex((item) => (
    item.path === '/' ? pathname === '/' || pathname === '/index' : pathname.startsWith(item.path)
  )));
  const activeIndex = interaction?.activeIndex ?? fallbackIndex;
  const pagePosition = useDerivedValue(() => {
    if (!interaction || interaction.interacting.value === 0 || interaction.toIndex.value < 0) {
      return activeIndex;
    }
    return interaction.fromIndex.value
      + ((interaction.toIndex.value - interaction.fromIndex.value) * interaction.progress.value);
  });
  const shellWidth = useDerivedValue(() => interpolate(
    pagePosition.value, [0, 1, 2], SHELL_WIDTHS, Extrapolation.CLAMP,
  ));
  const shellStyle = useAnimatedStyle(() => ({
    width: shellWidth.value,
    transform: [{
      scale: supportsNativeGlass ? 1 : interpolate(pressed.value, [0, 1], [1, 0.97]),
    }],
  }));
  const capsuleStyle = useAnimatedStyle(() => ({
    left: interpolate(pagePosition.value, [0, 1, 2], CAPSULE_X, Extrapolation.CLAMP),
    width: interpolate(pagePosition.value, [0, 1, 2], CAPSULE_WIDTH, Extrapolation.CLAMP),
  }));
  const layout = getBottomNavigationLayout(insets.bottom);

  return (
    <View pointerEvents="box-none" className="absolute inset-0">
      <LinearGradient
        pointerEvents="none"
        colors={['rgba(255,255,255,0)', '#FFFFFF']}
        locations={[0, 0.545645535]}
        className="absolute left-0 right-0"
        style={{ bottom: layout.fadeBottom, height: layout.fadeHeight }}
      />
      <View
        pointerEvents="box-none"
        className="absolute left-0 right-0 items-center"
        style={{ bottom: layout.navigationBottom }}
      >
        <Animated.View
          className="h-[60px] rounded-[32px]"
          style={[{
            shadowColor: BOTTOM_NAVIGATION_FIGMA.elevation.color,
            shadowOffset: { width: 0, height: BOTTOM_NAVIGATION_FIGMA.elevation.offsetY },
            shadowOpacity: BOTTOM_NAVIGATION_FIGMA.elevation.opacity,
            shadowRadius: BOTTOM_NAVIGATION_FIGMA.elevation.radius,
            backgroundColor: BOTTOM_NAVIGATION_FIGMA.elevation.casterColor,
            elevation: BOTTOM_NAVIGATION_FIGMA.elevation.elevation,
          }, shellStyle]}
        >
          <NavigationMaterial>
            <Animated.View
              pointerEvents="none"
              className="absolute rounded-[32px] bg-[rgba(15,16,16,0.06)]"
              style={[
                { top: 6 + CAPSULE_OPTICAL_OFFSET_Y, height: 48 },
                capsuleStyle,
              ]}
            />
          </NavigationMaterial>
          {BOTTOM_NAVIGATION_ITEMS.map((item, index) => (
            <SmoothDestination
              key={item.id}
              item={item}
              index={index}
              pagePosition={pagePosition}
              userId={userId}
              onPress={() => navigateWithMainNavigation(
                interaction, item.id, () => router.navigate(item.path as never),
              )}
              onPressIn={() => { pressed.value = withSpring(1, PRESS_SPRING); }}
              onPressOut={() => { pressed.value = withSpring(0, PRESS_SPRING); }}
            />
          ))}
        </Animated.View>
      </View>
    </View>
  );
}

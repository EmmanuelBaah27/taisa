import { useEffect, useRef } from 'react';
import { Platform, Pressable, Text, View, type ViewStyle } from 'react-native';
import { BlurView } from 'expo-blur';
import {
  GlassView,
  isGlassEffectAPIAvailable,
  isLiquidGlassAvailable,
} from 'expo-glass-effect';
import { LinearGradient } from 'expo-linear-gradient';
import { router, usePathname } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Animated, {
  Easing,
  useAnimatedStyle,
  useSharedValue,
  withSequence,
  withTiming,
} from 'react-native-reanimated';

import {
  BOTTOM_NAVIGATION_ITEMS,
  BOTTOM_NAVIGATION_ACTIVE_FILL,
  getBottomNavigationLayout,
  getBottomNavigationStateLayout,
  resolveGlassAvailability,
  type BottomNavigationItem,
} from '../../navigation/bottomNavigation';
import { useCareerStore } from '../../stores/careerStore';
import { Icon } from './Icon';
import { NaviiAvatar } from './NaviiAvatar';

const supportsNativeGlass =
  Platform.OS === 'ios'
  && resolveGlassAvailability(isGlassEffectAPIAvailable, isLiquidGlassAvailable);

const materialStyle: ViewStyle = {
  height: 60,
  overflow: 'hidden',
  borderRadius: 32,
  borderWidth: 1,
  borderColor: 'rgba(23,23,23,0.08)',
};

function NavigationMaterial({
  children,
  width,
}: {
  children: React.ReactNode;
  width: number;
}) {
  if (supportsNativeGlass) {
    return (
      <GlassView
        glassEffectStyle="regular"
        tintColor="rgba(255,255,255,0.10)"
        colorScheme="light"
        style={[materialStyle, { width }]}
      >
        {children}
      </GlassView>
    );
  }

  return (
    <BlurView
      intensity={45}
      tint="systemUltraThinMaterialLight"
      style={[materialStyle, { width }]}
    >
      <View
        pointerEvents="none"
        style={{
          position: 'absolute',
          inset: 0,
          backgroundColor: 'rgba(255,255,255,0.10)',
        }}
      />
      {children}
    </BlurView>
  );
}

function NavigationButton({
  item,
  active,
  itemIndex,
  activeIndex,
  width,
  userId,
  contentDirection,
}: {
  item: BottomNavigationItem;
  active: boolean;
  itemIndex: number;
  activeIndex: number;
  width: number;
  userId: string | null;
  contentDirection: 'row';
}) {
  const nudgeX = useSharedValue(0);
  const scale = useSharedValue(1);
  const previousActiveIndex = useRef(-1);
  const animatedStyle = useAnimatedStyle(() => ({
    transform: [{ translateX: nudgeX.value }, { scale: scale.value }],
  }));

  useEffect(() => {
    const previous = previousActiveIndex.current;
    previousActiveIndex.current = activeIndex;
    if (previous < 0 || previous === activeIndex) return;

    if (active) {
      scale.value = withSequence(
        withTiming(1.04, { duration: 100, easing: Easing.out(Easing.ease) }),
        withTiming(1, { duration: 180, easing: Easing.out(Easing.ease) }),
      );
      return;
    }

    if (Math.abs(itemIndex - activeIndex) === 1) {
      const outward = itemIndex < activeIndex ? -3 : 3;
      nudgeX.value = withSequence(
        withTiming(outward, { duration: 100, easing: Easing.out(Easing.ease) }),
        withTiming(0, { duration: 180, easing: Easing.out(Easing.ease) }),
      );
    }
  }, [active, activeIndex, itemIndex, nudgeX, scale]);

  return (
    <Animated.View
      style={[
        { width, height: 48 },
        animatedStyle,
      ]}
    >
      <Pressable
        accessibilityLabel={item.label}
        accessibilityRole="tab"
        accessibilityState={{ selected: active }}
        hitSlop={4}
        onPress={() => router.navigate(item.path as never)}
        style={({ pressed }) => [
          {
            width: '100%',
            height: 48,
            alignItems: 'center',
            justifyContent: 'center',
            borderRadius: 32,
          },
          active
            ? {
                paddingHorizontal: 16,
                paddingVertical: 12,
                backgroundColor: BOTTOM_NAVIGATION_ACTIVE_FILL,
              }
            : { padding: 12 },
          pressed && { opacity: 0.72 },
        ]}
      >
        <View
          style={{
            flexDirection: contentDirection,
            alignItems: 'center',
            gap: active ? 8 : 0,
          }}
        >
          {item.id === 'you' && userId ? (
            <View className="h-6 w-6 items-center justify-center overflow-hidden rounded-full">
              <NaviiAvatar seed={userId} size={32} />
            </View>
          ) : (
            <Icon name={item.icon} size={24} color={active ? '#0F1010' : '#898989'} />
          )}
          {active ? (
            <Text
              numberOfLines={1}
              className="font-inter-medium text-base text-[#0F1010]"
              style={{ lineHeight: 24, letterSpacing: -0.36 }}
            >
              {item.label}
            </Text>
          ) : null}
        </View>
      </Pressable>
    </Animated.View>
  );
}

export function BottomNavBar() {
  const pathname = usePathname();
  const insets = useSafeAreaInsets();
  const userId = useCareerStore((state) => state.userId);
  const layout = getBottomNavigationLayout(insets.bottom);
  const isActive = (path: string) => (
    path === '/' ? pathname === '/' || pathname === '/index' : pathname.startsWith(path)
  );
  const activeIndex = BOTTOM_NAVIGATION_ITEMS.findIndex((item) => isActive(item.path));
  const activeId = BOTTOM_NAVIGATION_ITEMS[activeIndex]?.id ?? 'logs';
  const stateLayout = getBottomNavigationStateLayout(activeId);

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
        <View
          className="h-[60px] rounded-[32px]"
          style={{
            width: stateLayout.navigationWidth,
            shadowColor: '#000000',
            shadowOffset: { width: 0, height: 0 },
            shadowOpacity: 0.04,
            shadowRadius: 28,
            elevation: 4,
          }}
        >
          <NavigationMaterial width={stateLayout.navigationWidth}>
            <View
              style={{
                width: stateLayout.navigationWidth - 2,
                height: 58,
                flexDirection: 'row',
                alignItems: 'center',
                gap: 4,
                padding: 5,
              }}
            >
              {BOTTOM_NAVIGATION_ITEMS.map((item, index) => (
                <NavigationButton
                  key={item.id}
                  item={item}
                  active={isActive(item.path)}
                  itemIndex={index}
                  activeIndex={activeIndex}
                  width={stateLayout.itemWidths[index]}
                  userId={userId}
                  contentDirection={stateLayout.activeContentDirection}
                />
              ))}
            </View>
          </NavigationMaterial>
        </View>
      </View>
    </View>
  );
}

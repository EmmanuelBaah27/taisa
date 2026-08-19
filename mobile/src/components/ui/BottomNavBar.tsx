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
  getBottomNavigationLayout,
  getBottomNavigationItemWidth,
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
  width: 240,
  height: 60,
  overflow: 'hidden',
  borderRadius: 32,
  borderWidth: 1,
  borderColor: 'rgba(23,23,23,0.08)',
};

function NavigationMaterial({ children }: { children: React.ReactNode }) {
  if (supportsNativeGlass) {
    return (
      <GlassView
        glassEffectStyle="regular"
        tintColor="rgba(255,255,255,0.10)"
        colorScheme="light"
        style={materialStyle}
      >
        {children}
      </GlassView>
    );
  }

  return (
    <BlurView
      intensity={45}
      tint="systemUltraThinMaterialLight"
      style={materialStyle}
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
  userId,
}: {
  item: BottomNavigationItem;
  active: boolean;
  itemIndex: number;
  activeIndex: number;
  userId: string | null;
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
        { width: getBottomNavigationItemWidth(active), height: 48 },
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
                flexDirection: 'row',
                gap: 8,
                paddingHorizontal: 16,
                paddingVertical: 12,
                backgroundColor: 'rgba(0,0,0,0.04)',
              }
            : { padding: 12 },
          pressed && { opacity: 0.72 },
        ]}
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
          className="h-[60px] w-[240px] rounded-[32px]"
          style={{
            shadowColor: '#000000',
            shadowOffset: { width: 0, height: 0 },
            shadowOpacity: 0.04,
            shadowRadius: 28,
            elevation: 4,
          }}
        >
          <NavigationMaterial>
            <View
              style={{
                width: 238,
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
                  userId={userId}
                />
              ))}
            </View>
          </NavigationMaterial>
        </View>
      </View>
    </View>
  );
}

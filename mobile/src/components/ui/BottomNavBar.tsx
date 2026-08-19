import { useEffect, useRef } from 'react';
import { Platform, View, type ViewStyle } from 'react-native';
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
  cancelAnimation,
  useAnimatedStyle,
  useReducedMotion,
  useSharedValue,
  withDelay,
  withSpring,
  withTiming,
} from 'react-native-reanimated';

import {
  BOTTOM_NAVIGATION_ITEMS,
  BOTTOM_NAVIGATION_FIGMA,
  getBottomNavigationLayout,
  getBottomNavigationStateLayout,
  resolveGlassAvailability,
  type BottomNavigationItem,
} from '../../navigation/bottomNavigation';
import { useCareerStore } from '../../stores/careerStore';
import { Icon } from './Icon';
import { InactiveNavigationItem } from './InactiveNavigationItem';
import { NaviiAvatar } from './NaviiAvatar';
import { SelectedNavigationItem } from './SelectedNavigationItem';

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
  width,
  userId,
  onNavigationPressIn,
  onNavigationPressOut,
}: {
  item: BottomNavigationItem;
  active: boolean;
  width: number;
  userId: string | null;
  onNavigationPressIn: () => void;
  onNavigationPressOut: () => void;
}) {
  const scaleX = useSharedValue(1);
  const scaleY = useSharedValue(1);
  const wasActive = useRef(active);
  const reduceMotion = useReducedMotion();
  const animatedStyle = useAnimatedStyle(() => ({
    transform: [
      { scaleX: scaleX.value },
      { scaleY: scaleY.value },
    ],
  }));
  const motion = BOTTOM_NAVIGATION_FIGMA.pressMotion;
  const easeOut = Easing.bezier(0.23, 1, 0.32, 1);
  useEffect(() => {
    const becameActive = active && !wasActive.current;
    wasActive.current = active;
    if (!becameActive) return;

    cancelAnimation(scaleX);
    cancelAnimation(scaleY);
    if (reduceMotion) {
      scaleX.value = 1;
      scaleY.value = 1;
      return;
    }

    scaleX.value = motion.pressedScaleX;
    scaleY.value = motion.pressedScaleY;
    const spring = {
      duration: motion.releaseDuration,
      bounce: motion.releaseBounce,
    };
    scaleX.value = withSpring(1, spring);
    scaleY.value = withSpring(1, spring);
  }, [active, motion, reduceMotion, scaleX, scaleY]);
  const handlePressIn = () => {
    onNavigationPressIn();
    cancelAnimation(scaleX);
    cancelAnimation(scaleY);
    if (reduceMotion) {
      scaleX.value = 1;
      scaleY.value = 1;
      return;
    }
    scaleX.value = withTiming(motion.pressedScaleX, {
      duration: motion.pressInDuration,
      easing: easeOut,
    });
    scaleY.value = withTiming(motion.pressedScaleY, {
      duration: motion.pressInDuration,
      easing: easeOut,
    });
  };
  const handlePressOut = () => {
    onNavigationPressOut();
    cancelAnimation(scaleX);
    cancelAnimation(scaleY);
    if (reduceMotion) {
      scaleX.value = 1;
      scaleY.value = 1;
      return;
    }
    const spring = {
      duration: motion.releaseDuration,
      bounce: motion.releaseBounce,
    };
    scaleX.value = withSpring(1, spring);
    scaleY.value = withSpring(1, spring);
  };
  return (
    <Animated.View
      style={[{ width, height: 48 }, active ? animatedStyle : undefined]}
    >
      {active ? (
        <SelectedNavigationItem
          label={item.label}
          width={width}
          onPress={() => router.navigate(item.path as never)}
          onPressIn={handlePressIn}
          onPressOut={handlePressOut}
          leadingVisual={item.id === 'you' && userId ? (
            <View className="h-6 w-6 items-center justify-center overflow-hidden rounded-full">
              <NaviiAvatar seed={userId} size={32} />
            </View>
          ) : (
            <Icon name={item.icon} size={24} color="#0F1010" />
          )}
        />
      ) : (
        <InactiveNavigationItem
          accessibilityLabel={item.label}
          icon={item.icon}
          onPress={() => router.navigate(item.path as never)}
          onPressIn={handlePressIn}
          onPressOut={handlePressOut}
          leadingVisual={item.id === 'you' && userId ? (
            <View className="h-6 w-6 items-center justify-center overflow-hidden rounded-full">
              <NaviiAvatar seed={userId} size={32} />
            </View>
          ) : undefined}
        />
      )}
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
  const shellScaleX = useSharedValue(1);
  const shellScaleY = useSharedValue(1);
  const reduceMotion = useReducedMotion();
  const shellMotion = BOTTOM_NAVIGATION_FIGMA.shellMotion;
  const shellStyle = useAnimatedStyle(() => ({
    transform: [{ scaleX: shellScaleX.value }, { scaleY: shellScaleY.value }],
  }));
  const handleNavigationPressIn = () => {
    cancelAnimation(shellScaleX);
    cancelAnimation(shellScaleY);
    if (reduceMotion) {
      shellScaleX.value = 1;
      shellScaleY.value = 1;
      return;
    }
    const easeOut = Easing.bezier(0.23, 1, 0.32, 1);
    shellScaleX.value = withDelay(
      shellMotion.pressDelay,
      withTiming(shellMotion.pressedScaleX, {
        duration: shellMotion.pressInDuration,
        easing: easeOut,
      }),
    );
    shellScaleY.value = withDelay(
      shellMotion.pressDelay,
      withTiming(shellMotion.pressedScaleY, {
        duration: shellMotion.pressInDuration,
        easing: easeOut,
      }),
    );
  };
  const handleNavigationPressOut = () => {
    cancelAnimation(shellScaleX);
    cancelAnimation(shellScaleY);
    if (reduceMotion) {
      shellScaleX.value = 1;
      shellScaleY.value = 1;
      return;
    }
    const spring = {
      duration: shellMotion.releaseDuration,
      bounce: shellMotion.releaseBounce,
    };
    shellScaleX.value = withSpring(1, spring);
    shellScaleY.value = withSpring(1, spring);
  };

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
          style={[
            {
              width: stateLayout.navigationWidth,
              shadowColor: '#000000',
              shadowOffset: { width: 0, height: 0 },
              shadowOpacity: 0.04,
              shadowRadius: 28,
              elevation: 4,
            },
            shellStyle,
          ]}
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
                  width={stateLayout.itemWidths[index]}
                  userId={userId}
                  onNavigationPressIn={handleNavigationPressIn}
                  onNavigationPressOut={handleNavigationPressOut}
                />
              ))}
            </View>
          </NavigationMaterial>
        </Animated.View>
      </View>
    </View>
  );
}

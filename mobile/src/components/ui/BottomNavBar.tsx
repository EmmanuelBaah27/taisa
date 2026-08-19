import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import {
  Animated as ReactNativeAnimated,
  Platform,
  Pressable,
  View,
  type StyleProp,
  type TextStyle,
  type ViewStyle,
} from 'react-native';
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
  runOnJS,
  useAnimatedStyle,
  useReducedMotion,
  useSharedValue,
  withSpring,
  withTiming,
} from 'react-native-reanimated';

import {
  BOTTOM_NAVIGATION_ACTIVE_FILL,
  BOTTOM_NAVIGATION_ITEMS,
  BOTTOM_NAVIGATION_FIGMA,
  getBottomNavigationCapsuleFrame,
  getBottomNavigationLayout,
  getBottomNavigationStateLayout,
  resolveGlassAvailability,
  settleBottomNavigationTransition,
  startBottomNavigationTransition,
  type BottomNavigationItem,
  type NavigationCapsuleState,
} from '../../navigation/bottomNavigation';
import { useCareerStore } from '../../stores/careerStore';
import { Icon } from './Icon';
import { NaviiAvatar } from './NaviiAvatar';
import { PersistentNavigationCapsule } from './PersistentNavigationCapsule';

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

const selectedItem = BOTTOM_NAVIGATION_FIGMA.selectedItem;
const inactiveItem = BOTTOM_NAVIGATION_FIGMA.inactiveItem;

function NavigationMaterial({
  children,
  width,
}: {
  children: ReactNode;
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

function NavigationLeadingVisual({
  item,
  selected,
  userId,
}: {
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
      color={selected ? '#0F1010' : inactiveItem.iconColor}
    />
  );
}

function NavigationDestination({
  item,
  selected,
  visualHidden,
  width,
  userId,
  onPress,
  onPressIn,
}: {
  item: BottomNavigationItem;
  selected: boolean;
  visualHidden: boolean;
  width: number;
  userId: string | null;
  onPress: () => void;
  onPressIn: () => void;
}) {
  return (
    <Pressable
      accessibilityLabel={item.label}
      accessibilityRole="tab"
      accessibilityState={{ selected }}
      hitSlop={4}
      onPress={onPress}
      onPressIn={onPressIn}
      style={{
        width,
        height: inactiveItem.height,
        alignItems: 'center',
        justifyContent: 'center',
      }}
    >
      <View style={{ opacity: visualHidden ? 0 : 1 }}>
        <NavigationLeadingVisual item={item} selected={false} userId={userId} />
      </View>
    </Pressable>
  );
}

function OutgoingNavigationContent({
  item,
  userId,
  labelStyle,
}: {
  item: BottomNavigationItem;
  userId: string | null;
  labelStyle: StyleProp<TextStyle>;
}) {
  const frame = getBottomNavigationCapsuleFrame(item.id);

  return (
    <View
      pointerEvents="none"
      style={{
        position: 'absolute',
        top: 6,
        left: frame.x,
        width: frame.width,
        height: selectedItem.height,
        alignItems: 'center',
        justifyContent: 'center',
        paddingHorizontal: selectedItem.paddingHorizontal,
        paddingVertical: selectedItem.paddingVertical,
      }}
    >
      <View className="flex-row items-center" style={{ gap: selectedItem.gap }}>
        <NavigationLeadingVisual item={item} selected userId={userId} />
        <ReactNativeAnimated.Text
          numberOfLines={1}
          className="font-sans-medium text-foreground"
          style={[
            {
              fontSize: selectedItem.fontSize,
              lineHeight: selectedItem.lineHeight,
              letterSpacing: selectedItem.letterSpacing,
            },
            labelStyle,
          ]}
        >
          {item.label}
        </ReactNativeAnimated.Text>
      </View>
    </View>
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
  const initialFrame = getBottomNavigationCapsuleFrame(activeId);
  const initialMotionState: NavigationCapsuleState = {
    from: activeId,
    to: activeId,
    phase: 'resting',
  };

  const transitionRef = useRef<NavigationCapsuleState>(initialMotionState);
  const transitionSequenceRef = useRef(0);
  const latestTransitionRef = useRef({ destination: activeId, sequence: 0 });
  const [motionState, setMotionState] = useState(initialMotionState);
  const stateLayout = getBottomNavigationStateLayout(motionState.to);
  const destinationFrame = getBottomNavigationCapsuleFrame(motionState.to);

  const reduceMotion = useReducedMotion();
  const shellMotion = BOTTOM_NAVIGATION_FIGMA.shellMotion;
  const labelMotion = BOTTOM_NAVIGATION_FIGMA.labelMotion;
  const shellScale = useSharedValue(1);
  const capsuleX = useSharedValue(initialFrame.x);
  const capsuleWidth = useSharedValue(initialFrame.width);
  const fillOpacity = useSharedValue(1);

  const incomingLabelOpacity = useRef(new ReactNativeAnimated.Value(1)).current;
  const incomingLabelScale = useRef(new ReactNativeAnimated.Value(1)).current;
  const incomingLabelTranslateX = useRef(new ReactNativeAnimated.Value(0)).current;
  const outgoingLabelOpacity = useRef(new ReactNativeAnimated.Value(0)).current;
  const outgoingLabelScale = useRef(new ReactNativeAnimated.Value(1)).current;
  const outgoingLabelTranslateX = useRef(new ReactNativeAnimated.Value(0)).current;

  const shellStyle = useAnimatedStyle(() => ({
    transform: [{ scale: shellScale.value }],
  }));
  const capsuleGeometryStyle = useAnimatedStyle(() => ({
    width: capsuleWidth.value,
    transform: [{ translateX: capsuleX.value }],
  }));
  const selectedFillStyle = useAnimatedStyle(() => ({
    opacity: fillOpacity.value,
  }));

  const incomingLabelStyle = {
    opacity: incomingLabelOpacity,
    transform: [
      { scale: incomingLabelScale },
      { translateX: incomingLabelTranslateX },
    ],
  } as unknown as StyleProp<TextStyle>;
  const outgoingLabelStyle = {
    opacity: outgoingLabelOpacity,
    transform: [
      { scale: outgoingLabelScale },
      { translateX: outgoingLabelTranslateX },
    ],
  } as unknown as StyleProp<TextStyle>;

  const finishCapsuleTransition = useCallback((
    destination: BottomNavigationItem['id'],
    sequence: number,
  ) => {
    const latest = latestTransitionRef.current;
    if (latest.destination !== destination || latest.sequence !== sequence) return;
    if (transitionRef.current.to !== destination) return;

    const settledState = settleBottomNavigationTransition(transitionRef.current);
    transitionRef.current = settledState;
    setMotionState(settledState);
    outgoingLabelOpacity.setValue(0);
    fillOpacity.value = withTiming(1, {
      duration: reduceMotion ? labelMotion.duration : 140,
      easing: Easing.out(Easing.quad),
    });

    if (reduceMotion) {
      shellScale.value = 1;
      return;
    }

    shellScale.value = withSpring(1, {
      duration: shellMotion.releaseDuration,
      dampingRatio: shellMotion.releaseDampingRatio,
    });
  }, [
    fillOpacity,
    labelMotion.duration,
    outgoingLabelOpacity,
    reduceMotion,
    shellMotion.releaseDampingRatio,
    shellMotion.releaseDuration,
    shellScale,
  ]);

  const beginLabelHandoff = useCallback((
    destination: BottomNavigationItem['id'],
    sequence: number,
  ) => {
    incomingLabelOpacity.stopAnimation();
    incomingLabelScale.stopAnimation();
    incomingLabelTranslateX.stopAnimation();
    outgoingLabelOpacity.stopAnimation();
    outgoingLabelScale.stopAnimation();
    outgoingLabelTranslateX.stopAnimation();

    incomingLabelOpacity.setValue(0);
    incomingLabelScale.setValue(reduceMotion ? 1 : labelMotion.enterScale);
    incomingLabelTranslateX.setValue(reduceMotion ? 0 : labelMotion.enterTranslateX);
    outgoingLabelOpacity.setValue(1);
    outgoingLabelScale.setValue(1);
    outgoingLabelTranslateX.setValue(0);

    const incoming = ReactNativeAnimated.parallel([
      ReactNativeAnimated.timing(incomingLabelOpacity, {
        toValue: 1,
        duration: labelMotion.duration,
        useNativeDriver: true,
      }),
      ReactNativeAnimated.timing(incomingLabelScale, {
        toValue: 1,
        duration: labelMotion.duration,
        useNativeDriver: true,
      }),
      ReactNativeAnimated.timing(incomingLabelTranslateX, {
        toValue: 0,
        duration: labelMotion.duration,
        useNativeDriver: true,
      }),
    ]);
    ReactNativeAnimated.parallel([
      ReactNativeAnimated.timing(outgoingLabelOpacity, {
        toValue: 0,
        duration: labelMotion.duration,
        useNativeDriver: true,
      }),
      ReactNativeAnimated.timing(outgoingLabelScale, {
        toValue: reduceMotion ? 1 : labelMotion.enterScale,
        duration: labelMotion.duration,
        useNativeDriver: true,
      }),
      ReactNativeAnimated.timing(outgoingLabelTranslateX, {
        toValue: reduceMotion ? 0 : labelMotion.enterTranslateX,
        duration: labelMotion.duration,
        useNativeDriver: true,
      }),
    ]).start();

    incoming.start(({ finished }) => {
      if (finished && reduceMotion) finishCapsuleTransition(destination, sequence);
    });
  }, [
    finishCapsuleTransition,
    incomingLabelOpacity,
    incomingLabelScale,
    incomingLabelTranslateX,
    labelMotion.duration,
    labelMotion.enterScale,
    labelMotion.enterTranslateX,
    outgoingLabelOpacity,
    outgoingLabelScale,
    outgoingLabelTranslateX,
    reduceMotion,
  ]);

  const beginCapsuleTransition = useCallback((
    destination: BottomNavigationItem['id'],
    sequence: number,
  ) => {
    const frame = getBottomNavigationCapsuleFrame(destination);
    beginLabelHandoff(destination, sequence);

    if (reduceMotion) {
      capsuleX.value = frame.x;
      capsuleWidth.value = frame.width;
      shellScale.value = 1;
      return;
    }

    capsuleWidth.value = withTiming(frame.width, {
      duration: 220,
      easing: Easing.bezier(0.77, 0, 0.175, 1),
    });
    capsuleX.value = withSpring(frame.x, {
      duration: 320,
      dampingRatio: 0.78,
    }, (finished) => {
      if (finished) runOnJS(finishCapsuleTransition)(destination, sequence);
    });
  }, [
    beginLabelHandoff,
    capsuleWidth,
    capsuleX,
    finishCapsuleTransition,
    reduceMotion,
    shellScale,
  ]);

  const handleNavigationPressIn = useCallback(() => {
    cancelAnimation(shellScale);
    if (reduceMotion) {
      shellScale.value = 1;
      return;
    }

    shellScale.value = withTiming(shellMotion.pressedScale, {
      duration: shellMotion.pressDuration,
      easing: Easing.bezier(0.23, 1, 0.32, 1),
    });
  }, [reduceMotion, shellMotion.pressDuration, shellMotion.pressedScale, shellScale]);

  const navigateTo = useCallback((item: BottomNavigationItem) => {
    const nextState = startBottomNavigationTransition(transitionRef.current, item.id);
    transitionRef.current = nextState;
    setMotionState(nextState);

    const sequence = transitionSequenceRef.current + 1;
    transitionSequenceRef.current = sequence;
    latestTransitionRef.current = { destination: item.id, sequence };

    if (nextState.phase === 'travelling') fillOpacity.value = 0;
    router.navigate(item.path as never);

    if (nextState.phase === 'travelling') {
      beginCapsuleTransition(item.id, sequence);
      return;
    }

    if (reduceMotion) {
      shellScale.value = 1;
    } else {
      shellScale.value = withSpring(1, {
        duration: shellMotion.releaseDuration,
        dampingRatio: shellMotion.releaseDampingRatio,
      });
    }
  }, [
    beginCapsuleTransition,
    fillOpacity,
    reduceMotion,
    shellMotion.releaseDampingRatio,
    shellMotion.releaseDuration,
    shellScale,
  ]);

  useEffect(() => {
    if (transitionRef.current.to === activeId) return;

    const frame = getBottomNavigationCapsuleFrame(activeId);
    const restingState: NavigationCapsuleState = {
      from: activeId,
      to: activeId,
      phase: 'resting',
    };
    transitionRef.current = restingState;
    latestTransitionRef.current = {
      destination: activeId,
      sequence: transitionSequenceRef.current,
    };
    setMotionState(restingState);
    capsuleX.value = frame.x;
    capsuleWidth.value = frame.width;
    fillOpacity.value = 1;
    shellScale.value = 1;
    incomingLabelOpacity.setValue(1);
    incomingLabelScale.setValue(1);
    incomingLabelTranslateX.setValue(0);
    outgoingLabelOpacity.setValue(0);
  }, [
    activeId,
    capsuleWidth,
    capsuleX,
    fillOpacity,
    incomingLabelOpacity,
    incomingLabelScale,
    incomingLabelTranslateX,
    outgoingLabelOpacity,
    shellScale,
  ]);

  const movingToId = motionState.to;
  const outgoingItem = BOTTOM_NAVIGATION_ITEMS.find((item) => item.id === motionState.from);
  const destinationItem = BOTTOM_NAVIGATION_ITEMS.find((item) => item.id === movingToId)
    ?? BOTTOM_NAVIGATION_ITEMS[1];

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
              {BOTTOM_NAVIGATION_ITEMS.map((item, index) => {
                const visualHidden = item.id === movingToId
                  || (motionState.phase !== 'resting' && item.id === motionState.from);

                return (
                  <NavigationDestination
                    key={item.id}
                    item={item}
                    selected={item.id === movingToId}
                    visualHidden={visualHidden}
                    width={stateLayout.itemWidths[index]}
                    userId={userId}
                    onPress={() => navigateTo(item)}
                    onPressIn={handleNavigationPressIn}
                  />
                );
              })}
            </View>

            <Animated.View
              pointerEvents="none"
              style={[
                {
                  position: 'absolute',
                  top: 6,
                  left: 0,
                  height: selectedItem.height,
                  borderRadius: selectedItem.borderRadius,
                  backgroundColor: BOTTOM_NAVIGATION_ACTIVE_FILL,
                },
                capsuleGeometryStyle,
                selectedFillStyle,
              ]}
            />

            {motionState.phase !== 'resting' && outgoingItem ? (
              <OutgoingNavigationContent
                item={outgoingItem}
                userId={userId}
                labelStyle={outgoingLabelStyle}
              />
            ) : null}

            <Animated.View
              pointerEvents="none"
              style={[
                {
                  position: 'absolute',
                  top: 0,
                  left: 0,
                  height: BOTTOM_NAVIGATION_FIGMA.navigationHeight,
                },
                capsuleGeometryStyle,
              ]}
            >
              <PersistentNavigationCapsule
                label={destinationItem.label}
                leadingVisual={(
                  <NavigationLeadingVisual item={destinationItem} selected userId={userId} />
                )}
                frame={{ ...destinationFrame, x: 0 }}
                phase={motionState.phase}
                animatedContainerStyle={{ backgroundColor: 'transparent' }}
                animatedLabelStyle={incomingLabelStyle}
              />
            </Animated.View>
          </NavigationMaterial>
        </Animated.View>
      </View>
    </View>
  );
}

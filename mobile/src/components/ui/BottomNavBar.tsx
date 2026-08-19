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
  BOTTOM_NAVIGATION_ITEMS,
  BOTTOM_NAVIGATION_FIGMA,
  getBottomNavigationCapsuleCenterOffset,
  getBottomNavigationCapsuleFrame,
  getBottomNavigationLayout,
  getBottomNavigationRenderPolicy,
  getBottomNavigationSurfaceTimeline,
  getBottomNavigationStateLayout,
  resolveGlassAvailability,
  settleBottomNavigationTransition,
  shouldReleaseBottomNavigationCancelledPress,
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
  width: '100%',
  height: 60,
  overflow: 'hidden',
  borderRadius: 32,
  borderWidth: 1,
  borderColor: 'rgba(23,23,23,0.08)',
};

const inactiveItem = BOTTOM_NAVIGATION_FIGMA.inactiveItem;

function NavigationMaterial({
  children,
}: {
  children: ReactNode;
}) {
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
  onPressOut,
}: {
  item: BottomNavigationItem;
  selected: boolean;
  visualHidden: boolean;
  width: number;
  userId: string | null;
  onPress: () => void;
  onPressIn: () => void;
  onPressOut: () => void;
}) {
  return (
    <Pressable
      accessibilityLabel={item.label}
      accessibilityRole="tab"
      accessibilityState={{ selected }}
      hitSlop={4}
      onPress={onPress}
      onPressIn={onPressIn}
      onPressOut={onPressOut}
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
  const mountedRef = useRef(true);
  const cancelledPressTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const pressAttemptRef = useRef({ sequence: 0, navigationCommitted: true });
  const [motionState, setMotionState] = useState(initialMotionState);
  const [outgoingLabel, setOutgoingLabel] = useState<BottomNavigationItem['label'] | null>(null);
  const stateLayout = getBottomNavigationStateLayout(motionState.to);
  const destinationFrame = getBottomNavigationCapsuleFrame(motionState.to);
  const renderPolicy = getBottomNavigationRenderPolicy(motionState);

  const reduceMotion = useReducedMotion();
  const shellMotion = BOTTOM_NAVIGATION_FIGMA.shellMotion;
  const capsuleMotion = BOTTOM_NAVIGATION_FIGMA.capsuleMotion;
  const labelMotion = BOTTOM_NAVIGATION_FIGMA.labelMotion;
  const reducedMotion = BOTTOM_NAVIGATION_FIGMA.reducedMotion;
  const surfaceTimeline = getBottomNavigationSurfaceTimeline(reduceMotion);
  const shellScale = useSharedValue(1);
  const shellWidth = useSharedValue(initialFrame.shellWidth);
  const capsuleX = useSharedValue(getBottomNavigationCapsuleCenterOffset(activeId));
  const capsuleWidth = useSharedValue(initialFrame.width);
  const selectedFillOpacity = useSharedValue(1);

  const selectedContentOpacity = useRef(new ReactNativeAnimated.Value(1)).current;
  const selectedLabelOpacity = useRef(new ReactNativeAnimated.Value(1)).current;
  const selectedLabelScale = useRef(new ReactNativeAnimated.Value(1)).current;
  const selectedLabelTranslateX = useRef(new ReactNativeAnimated.Value(0)).current;
  const outgoingLabelOpacity = useRef(new ReactNativeAnimated.Value(0)).current;
  const outgoingLabelScale = useRef(new ReactNativeAnimated.Value(1)).current;
  const outgoingLabelTranslateX = useRef(new ReactNativeAnimated.Value(0)).current;

  const shellStyle = useAnimatedStyle(() => ({
    width: shellWidth.value,
    transform: [{ scale: shellScale.value }],
  }));
  const capsuleGeometryStyle = useAnimatedStyle(() => ({
    width: capsuleWidth.value,
    transform: [{ translateX: capsuleX.value }],
  }));
  const selectedContentStyle = {
    opacity: selectedContentOpacity,
  } as unknown as StyleProp<ViewStyle>;
  const selectedLabelStyle = {
    opacity: selectedLabelOpacity,
    transform: [
      { scale: selectedLabelScale },
      { translateX: selectedLabelTranslateX },
    ],
  } as unknown as StyleProp<TextStyle>;
  const selectedFillStyle = useAnimatedStyle(() => ({
    opacity: selectedFillOpacity.value,
  }));
  const outgoingLabelStyle = {
    opacity: outgoingLabelOpacity,
    transform: [
      { scale: outgoingLabelScale },
      { translateX: outgoingLabelTranslateX },
    ],
  } as unknown as StyleProp<TextStyle>;

  const stopSelectedContentMotion = useCallback(() => {
    selectedContentOpacity.stopAnimation();
    selectedLabelOpacity.stopAnimation();
    selectedLabelScale.stopAnimation();
    selectedLabelTranslateX.stopAnimation();
    outgoingLabelOpacity.stopAnimation();
    outgoingLabelScale.stopAnimation();
    outgoingLabelTranslateX.stopAnimation();
  }, [
    selectedContentOpacity,
    selectedLabelOpacity,
    selectedLabelScale,
    selectedLabelTranslateX,
    outgoingLabelOpacity,
    outgoingLabelScale,
    outgoingLabelTranslateX,
  ]);

  const releaseShell = useCallback(() => {
    cancelAnimation(shellScale);
    if (reduceMotion) {
      shellScale.value = 1;
      return;
    }

    shellScale.value = withSpring(1, {
      duration: shellMotion.releaseDuration,
      dampingRatio: shellMotion.releaseDampingRatio,
    });
  }, [
    reduceMotion,
    shellMotion.releaseDampingRatio,
    shellMotion.releaseDuration,
    shellScale,
  ]);

  const finishCapsuleTransition = useCallback((
    destination: BottomNavigationItem['id'],
    sequence: number,
  ) => {
    if (!mountedRef.current) return;
    const latest = latestTransitionRef.current;
    if (latest.destination !== destination || latest.sequence !== sequence) return;
    if (transitionRef.current.to !== destination) return;

    const settledState = settleBottomNavigationTransition(transitionRef.current);
    transitionRef.current = settledState;
    setMotionState(settledState);
    setOutgoingLabel(null);

    if (reduceMotion) {
      selectedFillOpacity.value = 1;
      shellScale.value = 1;
      return;
    }

    selectedFillOpacity.value = withTiming(1, {
      duration: surfaceTimeline.fillRestoreDuration,
      easing: Easing.bezier(0.23, 1, 0.32, 1),
    });
    releaseShell();
  }, [
    reduceMotion,
    releaseShell,
    selectedFillOpacity,
    shellScale,
    surfaceTimeline,
  ]);

  const startSelectedContentMotion = useCallback((
    destination: BottomNavigationItem['id'],
    sequence: number,
  ) => {
    stopSelectedContentMotion();

    if (reduceMotion) {
      selectedContentOpacity.setValue(0);
      selectedLabelOpacity.setValue(1);
      selectedLabelScale.setValue(1);
      selectedLabelTranslateX.setValue(0);
      outgoingLabelOpacity.setValue(1);
      outgoingLabelScale.setValue(1);
      outgoingLabelTranslateX.setValue(0);
      ReactNativeAnimated.parallel([
        ReactNativeAnimated.timing(selectedContentOpacity, {
          toValue: 1,
          duration: reducedMotion.crossfadeDuration,
          useNativeDriver: true,
        }),
        ReactNativeAnimated.timing(outgoingLabelOpacity, {
          toValue: 0,
          duration: reducedMotion.crossfadeDuration,
          useNativeDriver: true,
        }),
      ]).start(({ finished }) => {
        if (finished) finishCapsuleTransition(destination, sequence);
      });
      return;
    }

    selectedContentOpacity.setValue(1);
    selectedLabelOpacity.setValue(0);
    selectedLabelScale.setValue(labelMotion.enterScale);
    selectedLabelTranslateX.setValue(labelMotion.enterTranslateX);
    outgoingLabelOpacity.setValue(1);
    outgoingLabelScale.setValue(1);
    outgoingLabelTranslateX.setValue(0);
    ReactNativeAnimated.parallel([
      ReactNativeAnimated.timing(selectedLabelOpacity, {
        toValue: 1,
        duration: labelMotion.duration,
        useNativeDriver: true,
      }),
      ReactNativeAnimated.timing(selectedLabelScale, {
        toValue: 1,
        duration: labelMotion.duration,
        useNativeDriver: true,
      }),
      ReactNativeAnimated.timing(selectedLabelTranslateX, {
        toValue: 0,
        duration: labelMotion.duration,
        useNativeDriver: true,
      }),
      ReactNativeAnimated.timing(outgoingLabelOpacity, {
        toValue: 0,
        duration: labelMotion.duration,
        useNativeDriver: true,
      }),
      ReactNativeAnimated.timing(outgoingLabelScale, {
        toValue: labelMotion.enterScale,
        duration: labelMotion.duration,
        useNativeDriver: true,
      }),
      ReactNativeAnimated.timing(outgoingLabelTranslateX, {
        toValue: labelMotion.enterTranslateX,
        duration: labelMotion.duration,
        useNativeDriver: true,
      }),
    ]).start();
  }, [
    finishCapsuleTransition,
    labelMotion.duration,
    labelMotion.enterScale,
    labelMotion.enterTranslateX,
    reduceMotion,
    reducedMotion.crossfadeDuration,
    selectedContentOpacity,
    selectedLabelOpacity,
    selectedLabelScale,
    selectedLabelTranslateX,
    outgoingLabelOpacity,
    outgoingLabelScale,
    outgoingLabelTranslateX,
    stopSelectedContentMotion,
  ]);

  const startCapsuleTransition = useCallback((
    destination: BottomNavigationItem['id'],
    sequence: number,
  ) => {
    const frame = getBottomNavigationCapsuleFrame(destination);
    const centerOffset = getBottomNavigationCapsuleCenterOffset(destination);
    startSelectedContentMotion(destination, sequence);

    if (reduceMotion) {
      cancelAnimation(capsuleX);
      cancelAnimation(capsuleWidth);
      cancelAnimation(shellWidth);
      cancelAnimation(selectedFillOpacity);
      capsuleX.value = centerOffset;
      capsuleWidth.value = frame.width;
      shellWidth.value = frame.shellWidth;
      shellScale.value = 1;
      selectedFillOpacity.value = withTiming(0, {
        duration: reducedMotion.crossfadeDuration / 2,
      }, (finished) => {
        if (finished) {
          selectedFillOpacity.value = withTiming(1, {
            duration: reducedMotion.crossfadeDuration / 2,
          });
        }
      });
      return;
    }

    const coordinatedSpring = {
      duration: capsuleMotion.duration,
      dampingRatio: capsuleMotion.dampingRatio,
    };
    capsuleWidth.value = withSpring(frame.width, coordinatedSpring);
    shellWidth.value = withSpring(frame.shellWidth, coordinatedSpring);
    capsuleX.value = withSpring(centerOffset, coordinatedSpring, (finished) => {
      if (finished) runOnJS(finishCapsuleTransition)(destination, sequence);
    });
  }, [
    capsuleMotion.dampingRatio,
    capsuleMotion.duration,
    capsuleWidth,
    capsuleX,
    finishCapsuleTransition,
    reduceMotion,
    reducedMotion.crossfadeDuration,
    selectedFillOpacity,
    shellScale,
    shellWidth,
    startSelectedContentMotion,
  ]);

  const handleNavigationPressIn = useCallback(() => {
    if (cancelledPressTimerRef.current) {
      clearTimeout(cancelledPressTimerRef.current);
      cancelledPressTimerRef.current = null;
    }
    pressAttemptRef.current = {
      sequence: pressAttemptRef.current.sequence + 1,
      navigationCommitted: false,
    };
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

  const handleNavigationPressOut = useCallback(() => {
    const pressSequence = pressAttemptRef.current.sequence;
    cancelledPressTimerRef.current = setTimeout(() => {
      cancelledPressTimerRef.current = null;
      if (!mountedRef.current) return;
      if (pressAttemptRef.current.sequence !== pressSequence) return;
      if (!shouldReleaseBottomNavigationCancelledPress(
        pressAttemptRef.current.navigationCommitted,
        transitionRef.current,
      )) return;

      releaseShell();
    }, 0);
  }, [releaseShell]);

  const navigateTo = useCallback((item: BottomNavigationItem) => {
    pressAttemptRef.current.navigationCommitted = true;
    if (transitionRef.current.to === item.id) {
      router.navigate(item.path as never);
      if (transitionRef.current.phase === 'resting') releaseShell();
      return;
    }

    const nextState = startBottomNavigationTransition(transitionRef.current, item.id);
    const previousItem = BOTTOM_NAVIGATION_ITEMS.find(
      (destination) => destination.id === transitionRef.current.to,
    );
    setOutgoingLabel(previousItem?.label ?? null);
    transitionRef.current = nextState;
    setMotionState(nextState);

    const sequence = transitionSequenceRef.current + 1;
    transitionSequenceRef.current = sequence;
    latestTransitionRef.current = { destination: item.id, sequence };

    cancelAnimation(selectedFillOpacity);
    selectedFillOpacity.value = withTiming(0, {
      duration: reduceMotion
        ? reducedMotion.crossfadeDuration / 2
        : surfaceTimeline.fillFadeOutDuration,
      easing: Easing.bezier(0.23, 1, 0.32, 1),
    });
    startCapsuleTransition(item.id, sequence);
    router.navigate(item.path as never);
  }, [
    reduceMotion,
    reducedMotion.crossfadeDuration,
    releaseShell,
    selectedFillOpacity,
    startCapsuleTransition,
    surfaceTimeline,
  ]);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      if (cancelledPressTimerRef.current) {
        clearTimeout(cancelledPressTimerRef.current);
        cancelledPressTimerRef.current = null;
      }
      stopSelectedContentMotion();
      cancelAnimation(shellScale);
      cancelAnimation(capsuleX);
      cancelAnimation(capsuleWidth);
      cancelAnimation(shellWidth);
      cancelAnimation(selectedFillOpacity);
    };
  }, [
    capsuleWidth,
    capsuleX,
    selectedFillOpacity,
    shellScale,
    shellWidth,
    stopSelectedContentMotion,
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
    cancelAnimation(capsuleX);
    cancelAnimation(capsuleWidth);
    cancelAnimation(shellWidth);
    cancelAnimation(selectedFillOpacity);
    capsuleX.value = getBottomNavigationCapsuleCenterOffset(activeId);
    capsuleWidth.value = frame.width;
    shellWidth.value = frame.shellWidth;
    selectedFillOpacity.value = 1;
    shellScale.value = 1;
    stopSelectedContentMotion();
    selectedContentOpacity.setValue(1);
    selectedLabelOpacity.setValue(1);
    selectedLabelScale.setValue(1);
    selectedLabelTranslateX.setValue(0);
    outgoingLabelOpacity.setValue(0);
    outgoingLabelScale.setValue(1);
    outgoingLabelTranslateX.setValue(0);
    setOutgoingLabel(null);
  }, [
    activeId,
    capsuleWidth,
    capsuleX,
    outgoingLabelOpacity,
    outgoingLabelScale,
    outgoingLabelTranslateX,
    selectedFillOpacity,
    selectedContentOpacity,
    selectedLabelOpacity,
    selectedLabelScale,
    selectedLabelTranslateX,
    shellScale,
    shellWidth,
    stopSelectedContentMotion,
  ]);

  const destinationItem = BOTTOM_NAVIGATION_ITEMS.find((item) => item.id === motionState.to)
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
              shadowColor: '#000000',
              shadowOffset: { width: 0, height: 0 },
              shadowOpacity: 0.04,
              shadowRadius: 28,
              elevation: 4,
            },
            shellStyle,
          ]}
        >
          <NavigationMaterial>
            <View
              style={{
                width: '100%',
                height: 58,
                flexDirection: 'row',
                alignItems: 'center',
                gap: 4,
                padding: 5,
              }}
            >
              {BOTTOM_NAVIGATION_ITEMS.map((item, index) => (
                <NavigationDestination
                  key={item.id}
                  item={item}
                  selected={item.id === motionState.to}
                  visualHidden={item.id === renderPolicy.hiddenStableDestination}
                  width={stateLayout.itemWidths[index]}
                  userId={userId}
                  onPress={() => navigateTo(item)}
                  onPressIn={handleNavigationPressIn}
                  onPressOut={handleNavigationPressOut}
                />
              ))}
            </View>

            <Animated.View
              pointerEvents="none"
              style={[
                {
                  position: 'absolute',
                  top: 0,
                  left: '50%',
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
                outgoingLabel={renderPolicy.outgoingLabelLayers ? outgoingLabel ?? undefined : undefined}
                animatedContainerStyle={[
                  { width: '100%' },
                ]}
                animatedContentStyle={selectedContentStyle}
                animatedFillStyle={selectedFillStyle}
                animatedLabelStyle={selectedLabelStyle}
                animatedOutgoingLabelStyle={outgoingLabelStyle}
              />
            </Animated.View>
          </NavigationMaterial>
        </Animated.View>
      </View>
    </View>
  );
}

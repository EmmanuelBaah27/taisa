import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type ReactNode,
} from 'react';
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
  getBottomNavigationContentHandoffPolicy,
  getBottomNavigationCapsuleCenterOffset,
  getBottomNavigationCapsuleFrame,
  getBottomNavigationLayout,
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
  height: 60,
  overflow: 'hidden',
  borderRadius: 32,
  borderWidth: 1,
  borderColor: 'rgba(23,23,23,0.08)',
};

const selectedItem = BOTTOM_NAVIGATION_FIGMA.selectedItem;
const inactiveItem = BOTTOM_NAVIGATION_FIGMA.inactiveItem;

interface NavigationContentMotion {
  opacity: ReactNativeAnimated.Value;
  scale: ReactNativeAnimated.Value;
  translateX: ReactNativeAnimated.Value;
}

function createNavigationContentMotion({
  opacity,
  scale,
  translateX,
}: {
  opacity: number;
  scale: number;
  translateX: number;
}): NavigationContentMotion {
  return {
    opacity: new ReactNativeAnimated.Value(opacity),
    scale: new ReactNativeAnimated.Value(scale),
    translateX: new ReactNativeAnimated.Value(translateX),
  };
}

function stopNavigationContentMotion(motion: NavigationContentMotion) {
  motion.opacity.stopAnimation();
  motion.scale.stopAnimation();
  motion.translateX.stopAnimation();
}

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

function OutgoingNavigationContent({
  item,
  userId,
  labelStyle,
  contentStyle,
  followsCapsule,
  capsuleStyle,
}: {
  item: BottomNavigationItem;
  userId: string | null;
  labelStyle: StyleProp<TextStyle>;
  contentStyle: StyleProp<ViewStyle>;
  followsCapsule: boolean;
  capsuleStyle: StyleProp<ViewStyle>;
}) {
  const frame = getBottomNavigationCapsuleFrame(item.id);
  const centerOffset = getBottomNavigationCapsuleCenterOffset(item.id);

  return (
    <Animated.View
      pointerEvents="none"
      style={[
        {
          position: 'absolute',
          top: 0,
          left: '50%',
          width: frame.width,
          height: BOTTOM_NAVIGATION_FIGMA.navigationHeight,
          transform: [{ translateX: centerOffset }],
        },
        followsCapsule ? capsuleStyle : undefined,
      ]}
    >
      <ReactNativeAnimated.View
        style={[
          {
            position: 'absolute',
            inset: 0,
          },
          contentStyle,
        ]}
      >
        <View
          style={{
            position: 'absolute',
            top: 6,
            left: 0,
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
      </ReactNativeAnimated.View>
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
  const initialFrame = getBottomNavigationCapsuleFrame(activeId);
  const initialCenterOffset = getBottomNavigationCapsuleCenterOffset(activeId);
  const initialMotionState: NavigationCapsuleState = {
    from: activeId,
    to: activeId,
    phase: 'resting',
  };

  const transitionRef = useRef<NavigationCapsuleState>(initialMotionState);
  const transitionSequenceRef = useRef(0);
  const latestTransitionRef = useRef({ destination: activeId, sequence: 0 });
  const pendingTransitionRef = useRef<{
    destination: BottomNavigationItem['id'];
    sequence: number;
  } | null>(null);
  const mountedRef = useRef(true);
  const cancelledPressTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const pressAttemptRef = useRef({ sequence: 0, navigationCommitted: true });
  const [motionState, setMotionState] = useState(initialMotionState);
  const [outgoingFollowsCapsule, setOutgoingFollowsCapsule] = useState(false);
  const stateLayout = getBottomNavigationStateLayout(motionState.to);
  const destinationFrame = getBottomNavigationCapsuleFrame(motionState.to);

  const reduceMotion = useReducedMotion();
  const shellMotion = BOTTOM_NAVIGATION_FIGMA.shellMotion;
  const labelMotion = BOTTOM_NAVIGATION_FIGMA.labelMotion;
  const reducedMotion = BOTTOM_NAVIGATION_FIGMA.reducedMotion;
  const shellScale = useSharedValue(1);
  const capsuleX = useSharedValue(initialCenterOffset);
  const capsuleWidth = useSharedValue(initialFrame.width);
  const fillOpacity = useSharedValue(1);
  const outgoingFillOpacity = useSharedValue(0);
  const incomingContentMotionRef = useRef<NavigationContentMotion | null>(null);
  const outgoingContentMotionRef = useRef<NavigationContentMotion | null>(null);
  if (!incomingContentMotionRef.current) {
    incomingContentMotionRef.current = createNavigationContentMotion({
      opacity: 1,
      scale: 1,
      translateX: 0,
    });
  }
  if (!outgoingContentMotionRef.current) {
    outgoingContentMotionRef.current = createNavigationContentMotion({
      opacity: 0,
      scale: 1,
      translateX: 0,
    });
  }

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
  const outgoingFillStyle = useAnimatedStyle(() => ({
    opacity: outgoingFillOpacity.value,
  }));

  const incomingContentMotion = incomingContentMotionRef.current;
  const outgoingContentMotion = outgoingContentMotionRef.current;
  const incomingContentStyle = {
    opacity: incomingContentMotion.opacity,
  } as unknown as StyleProp<ViewStyle>;
  const outgoingContentStyle = {
    opacity: outgoingContentMotion.opacity,
  } as unknown as StyleProp<ViewStyle>;

  const incomingLabelStyle = {
    transform: [
      { scale: incomingContentMotion.scale },
      { translateX: incomingContentMotion.translateX },
    ],
  } as unknown as StyleProp<TextStyle>;
  const outgoingLabelStyle = {
    transform: [
      { scale: outgoingContentMotion.scale },
      { translateX: outgoingContentMotion.translateX },
    ],
  } as unknown as StyleProp<TextStyle>;

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
    setOutgoingFollowsCapsule(false);
    if (outgoingContentMotionRef.current) {
      outgoingContentMotionRef.current.opacity.setValue(0);
    }
    outgoingFillOpacity.value = 0;

    if (reduceMotion) {
      if (incomingContentMotionRef.current) {
        incomingContentMotionRef.current.opacity.setValue(1);
      }
      fillOpacity.value = 1;
      shellScale.value = 1;
      return;
    }

    fillOpacity.value = withTiming(1, {
      duration: 140,
      easing: Easing.out(Easing.quad),
    });
    releaseShell();
  }, [
    fillOpacity,
    outgoingFillOpacity,
    reduceMotion,
    releaseShell,
    shellScale,
  ]);

  const prepareContentHandoff = useCallback((preserveIncomingValues: boolean) => {
    const currentIncoming = incomingContentMotionRef.current;
    const previousOutgoing = outgoingContentMotionRef.current;
    if (!currentIncoming || !previousOutgoing) return;

    stopNavigationContentMotion(previousOutgoing);
    stopNavigationContentMotion(currentIncoming);
    if (!preserveIncomingValues) {
      currentIncoming.opacity.setValue(1);
      currentIncoming.scale.setValue(1);
      currentIncoming.translateX.setValue(0);
    }
    if (reduceMotion) {
      currentIncoming.scale.setValue(1);
      currentIncoming.translateX.setValue(0);
    }

    outgoingContentMotionRef.current = currentIncoming;
    incomingContentMotionRef.current = createNavigationContentMotion({
      opacity: 0,
      scale: reduceMotion ? 1 : labelMotion.enterScale,
      translateX: reduceMotion ? 0 : labelMotion.enterTranslateX,
    });
  }, [labelMotion.enterScale, labelMotion.enterTranslateX, reduceMotion]);

  const beginContentHandoff = useCallback((
    destination: BottomNavigationItem['id'],
    sequence: number,
  ) => {
    const incoming = incomingContentMotionRef.current;
    const outgoing = outgoingContentMotionRef.current;
    if (!incoming || !outgoing) return;

    const duration = reduceMotion
      ? reducedMotion.crossfadeDuration
      : labelMotion.duration;
    const incomingAnimation = ReactNativeAnimated.parallel([
      ReactNativeAnimated.timing(incoming.opacity, {
        toValue: 1,
        duration,
        useNativeDriver: true,
      }),
      ReactNativeAnimated.timing(incoming.scale, {
        toValue: 1,
        duration,
        useNativeDriver: true,
      }),
      ReactNativeAnimated.timing(incoming.translateX, {
        toValue: 0,
        duration,
        useNativeDriver: true,
      }),
    ]);
    ReactNativeAnimated.parallel([
      ReactNativeAnimated.timing(outgoing.opacity, {
        toValue: 0,
        duration,
        useNativeDriver: true,
      }),
      ReactNativeAnimated.timing(outgoing.scale, {
        toValue: reduceMotion ? 1 : labelMotion.enterScale,
        duration,
        useNativeDriver: true,
      }),
      ReactNativeAnimated.timing(outgoing.translateX, {
        toValue: reduceMotion ? 0 : labelMotion.enterTranslateX,
        duration,
        useNativeDriver: true,
      }),
    ]).start();

    incomingAnimation.start(({ finished }) => {
      if (finished && reduceMotion) finishCapsuleTransition(destination, sequence);
    });
  }, [
    finishCapsuleTransition,
    labelMotion.duration,
    labelMotion.enterScale,
    labelMotion.enterTranslateX,
    reduceMotion,
    reducedMotion.crossfadeDuration,
  ]);

  const beginCapsuleTransition = useCallback((
    destination: BottomNavigationItem['id'],
    sequence: number,
  ) => {
    const frame = getBottomNavigationCapsuleFrame(destination);
    const centerOffset = getBottomNavigationCapsuleCenterOffset(destination);
    beginContentHandoff(destination, sequence);

    if (reduceMotion) {
      cancelAnimation(fillOpacity);
      cancelAnimation(outgoingFillOpacity);
      outgoingFillOpacity.value = fillOpacity.value;
      fillOpacity.value = 0;
      capsuleX.value = centerOffset;
      capsuleWidth.value = frame.width;
      shellScale.value = 1;

      const crossfade = {
        duration: reducedMotion.crossfadeDuration,
        easing: Easing.out(Easing.quad),
      };
      outgoingFillOpacity.value = withTiming(0, crossfade);
      fillOpacity.value = withTiming(1, crossfade);
      return;
    }

    outgoingFillOpacity.value = 0;
    capsuleWidth.value = withTiming(frame.width, {
      duration: 220,
      easing: Easing.bezier(0.77, 0, 0.175, 1),
    });
    capsuleX.value = withSpring(centerOffset, {
      duration: 320,
      dampingRatio: 0.78,
    }, (finished) => {
      if (finished) runOnJS(finishCapsuleTransition)(destination, sequence);
    });
  }, [
    beginContentHandoff,
    capsuleWidth,
    capsuleX,
    fillOpacity,
    finishCapsuleTransition,
    outgoingFillOpacity,
    reduceMotion,
    reducedMotion.crossfadeDuration,
    shellScale,
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

    const previousState = transitionRef.current;
    const handoffPolicy = getBottomNavigationContentHandoffPolicy(
      previousState,
      Boolean(reduceMotion),
    );
    prepareContentHandoff(handoffPolicy.preserveIncomingValues);
    const nextState = startBottomNavigationTransition(previousState, item.id);
    transitionRef.current = nextState;
    setMotionState(nextState);
    setOutgoingFollowsCapsule(handoffPolicy.outgoingFollowsCapsule);

    const sequence = transitionSequenceRef.current + 1;
    transitionSequenceRef.current = sequence;
    latestTransitionRef.current = { destination: item.id, sequence };

    if (nextState.phase === 'travelling' && !reduceMotion) fillOpacity.value = 0;
    if (nextState.phase === 'travelling') {
      pendingTransitionRef.current = { destination: item.id, sequence };
    }
    router.navigate(item.path as never);

    if (nextState.phase === 'travelling') return;

    releaseShell();
  }, [
    fillOpacity,
    prepareContentHandoff,
    reduceMotion,
    releaseShell,
  ]);

  useLayoutEffect(() => {
    const pending = pendingTransitionRef.current;
    if (!pending || motionState.phase === 'resting') return;
    if (pending.destination !== motionState.to) return;
    if (latestTransitionRef.current.sequence !== pending.sequence) return;

    pendingTransitionRef.current = null;
    beginCapsuleTransition(pending.destination, pending.sequence);
  }, [beginCapsuleTransition, motionState]);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      pendingTransitionRef.current = null;
      if (cancelledPressTimerRef.current) {
        clearTimeout(cancelledPressTimerRef.current);
        cancelledPressTimerRef.current = null;
      }

      if (incomingContentMotionRef.current) {
        stopNavigationContentMotion(incomingContentMotionRef.current);
      }
      if (outgoingContentMotionRef.current) {
        stopNavigationContentMotion(outgoingContentMotionRef.current);
      }
      cancelAnimation(shellScale);
      cancelAnimation(capsuleX);
      cancelAnimation(capsuleWidth);
      cancelAnimation(fillOpacity);
      cancelAnimation(outgoingFillOpacity);
    };
  }, [
    capsuleWidth,
    capsuleX,
    fillOpacity,
    outgoingFillOpacity,
    shellScale,
  ]);

  useEffect(() => {
    if (transitionRef.current.to === activeId) return;

    const frame = getBottomNavigationCapsuleFrame(activeId);
    const centerOffset = getBottomNavigationCapsuleCenterOffset(activeId);
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
    setOutgoingFollowsCapsule(false);
    capsuleX.value = centerOffset;
    capsuleWidth.value = frame.width;
    fillOpacity.value = 1;
    outgoingFillOpacity.value = 0;
    shellScale.value = 1;
    if (incomingContentMotionRef.current) {
      stopNavigationContentMotion(incomingContentMotionRef.current);
    }
    if (outgoingContentMotionRef.current) {
      stopNavigationContentMotion(outgoingContentMotionRef.current);
    }
    incomingContentMotionRef.current = createNavigationContentMotion({
      opacity: 1,
      scale: 1,
      translateX: 0,
    });
    outgoingContentMotionRef.current = createNavigationContentMotion({
      opacity: 0,
      scale: 1,
      translateX: 0,
    });
  }, [
    activeId,
    capsuleWidth,
    capsuleX,
    fillOpacity,
    outgoingFillOpacity,
    shellScale,
  ]);

  const movingToId = motionState.to;
  const outgoingItem = BOTTOM_NAVIGATION_ITEMS.find((item) => item.id === motionState.from);
  const outgoingFrame = getBottomNavigationCapsuleFrame(motionState.from);
  const outgoingCenterOffset = getBottomNavigationCapsuleCenterOffset(motionState.from);
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
                    onPressOut={handleNavigationPressOut}
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
                  left: '50%',
                  width: outgoingFrame.width,
                  height: selectedItem.height,
                  borderRadius: selectedItem.borderRadius,
                  backgroundColor: BOTTOM_NAVIGATION_ACTIVE_FILL,
                  transform: [{ translateX: outgoingCenterOffset }],
                },
                outgoingFillStyle,
              ]}
            />

            <Animated.View
              pointerEvents="none"
              style={[
                {
                  position: 'absolute',
                  top: 6,
                  left: '50%',
                  height: selectedItem.height,
                  borderRadius: selectedItem.borderRadius,
                  backgroundColor: BOTTOM_NAVIGATION_ACTIVE_FILL,
                },
                capsuleGeometryStyle,
                selectedFillStyle,
              ]}
            />

            {outgoingItem ? (
              <OutgoingNavigationContent
                item={outgoingItem}
                userId={userId}
                labelStyle={outgoingLabelStyle}
                contentStyle={outgoingContentStyle}
                followsCapsule={outgoingFollowsCapsule}
                capsuleStyle={capsuleGeometryStyle}
              />
            ) : null}

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
                animatedContainerStyle={[
                  { backgroundColor: 'transparent' },
                  incomingContentStyle,
                ]}
                animatedLabelStyle={incomingLabelStyle}
              />
            </Animated.View>
          </NavigationMaterial>
        </Animated.View>
      </View>
    </View>
  );
}

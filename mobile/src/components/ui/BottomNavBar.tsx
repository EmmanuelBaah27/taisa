import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import {
  AccessibilityInfo,
  Animated as ReactNativeAnimated,
  Easing,
  Platform,
  Pressable,
  View,
  type StyleProp,
  type TextStyle,
  type ViewStyle,
} from 'react-native';
import { BlurView } from 'expo-blur';
import { LinearGradient } from 'expo-linear-gradient';
import { router, usePathname } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import {
  BOTTOM_NAVIGATION_ITEMS,
  BOTTOM_NAVIGATION_FIGMA,
  BOTTOM_NAVIGATION_FALLBACK_GLASS,
  getBottomNavigationCapsuleCenterOffset,
  getBottomNavigationCapsuleFrame,
  getBottomNavigationDestinationOffsets,
  getBottomNavigationLayout,
  getBottomNavigationRenderPolicy,
  getBottomNavigationSurfaceTimeline,
  resolveGlassAvailability,
  resolveOptionalGlassModule,
  settleBottomNavigationTransition,
  startBottomNavigationTransition,
  type BottomNavigationItem,
  type NavigationCapsuleState,
} from '../../navigation/bottomNavigation';
import { useCareerStore } from '../../stores/careerStore';
import { Icon } from './Icon';
import { NaviiAvatar } from './NaviiAvatar';
import { PersistentNavigationCapsule } from './PersistentNavigationCapsule';

const nativeGlassEnabled = process.env.EXPO_PUBLIC_NATIVE_GLASS_ENABLED === 'true';
const glassEffectModule = resolveOptionalGlassModule(
  nativeGlassEnabled,
  () => require('expo-glass-effect') as typeof import('expo-glass-effect'),
);
const NativeGlassView = glassEffectModule?.GlassView;

const supportsNativeGlass =
  Platform.OS === 'ios'
  && glassEffectModule !== null
  && resolveGlassAvailability(
    glassEffectModule.isGlassEffectAPIAvailable,
    glassEffectModule.isLiquidGlassAvailable,
  );

const materialStyle: ViewStyle = {
  width: '100%',
  height: 60,
  overflow: 'hidden',
  borderRadius: 32,
  borderWidth: 1,
  borderColor: BOTTOM_NAVIGATION_FALLBACK_GLASS.borderColor,
};

const inactiveItem = BOTTOM_NAVIGATION_FIGMA.inactiveItem;

function NavigationMaterial({
  children,
}: {
  children: ReactNode;
}) {
  if (supportsNativeGlass && NativeGlassView) {
    return (
      <NativeGlassView
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
        style={{
          position: 'absolute',
          inset: 0,
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
  centerOffset,
  userId,
  onPress,
  onPressIn,
  onPressOut,
}: {
  item: BottomNavigationItem;
  selected: boolean;
  visualHidden: boolean;
  centerOffset: number | ReactNativeAnimated.Value;
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
        position: 'absolute',
        top: 5,
        left: '50%',
        width: inactiveItem.width,
        height: inactiveItem.height,
        alignItems: 'center',
        justifyContent: 'center',
        transform: [
          { translateX: centerOffset },
          { translateX: -(inactiveItem.width / 2) },
        ],
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
  const initialDestinationOffsets = getBottomNavigationDestinationOffsets(activeId);
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
  const pressAttemptRef = useRef<{
    sequence: number;
    navigationCommitted: boolean;
    origin: BottomNavigationItem['id'];
    destination: BottomNavigationItem['id'] | null;
  }>({ sequence: 0, navigationCommitted: true, origin: activeId, destination: null });
  const [motionState, setMotionState] = useState(initialMotionState);
  const [outgoingLabel, setOutgoingLabel] = useState<BottomNavigationItem['label'] | null>(null);
  const destinationFrame = getBottomNavigationCapsuleFrame(motionState.to);
  const renderPolicy = getBottomNavigationRenderPolicy(motionState);

  const [reduceMotion, setReduceMotion] = useState(false);
  const shellMotion = BOTTOM_NAVIGATION_FIGMA.shellMotion;
  const capsuleMotion = BOTTOM_NAVIGATION_FIGMA.capsuleMotion;
  const labelMotion = BOTTOM_NAVIGATION_FIGMA.labelMotion;
  const reducedMotion = BOTTOM_NAVIGATION_FIGMA.reducedMotion;
  const surfaceTimeline = getBottomNavigationSurfaceTimeline(reduceMotion);
  const shellScale = useRef(new ReactNativeAnimated.Value(1)).current;
  const shellWidth = useRef(new ReactNativeAnimated.Value(initialFrame.shellWidth)).current;
  const capsuleX = useRef(
    new ReactNativeAnimated.Value(getBottomNavigationCapsuleCenterOffset(activeId)),
  ).current;
  const capsuleWidth = useRef(new ReactNativeAnimated.Value(initialFrame.width)).current;
  const destinationOffsets = useRef(
    initialDestinationOffsets.map((offset) => new ReactNativeAnimated.Value(offset)),
  ).current;
  const selectedFillOpacity = useRef(new ReactNativeAnimated.Value(1)).current;

  const selectedContentOpacity = useRef(new ReactNativeAnimated.Value(1)).current;
  const selectedLabelOpacity = useRef(new ReactNativeAnimated.Value(1)).current;
  const selectedLabelScale = useRef(new ReactNativeAnimated.Value(1)).current;
  const selectedLabelTranslateX = useRef(new ReactNativeAnimated.Value(0)).current;
  const outgoingLabelOpacity = useRef(new ReactNativeAnimated.Value(0)).current;
  const outgoingLabelScale = useRef(new ReactNativeAnimated.Value(1)).current;
  const outgoingLabelTranslateX = useRef(new ReactNativeAnimated.Value(0)).current;

  const shellStyle = {
    width: shellWidth,
    transform: [{ scale: shellScale }],
  } as unknown as StyleProp<ViewStyle>;
  const capsuleGeometryStyle = {
    width: capsuleWidth,
    transform: [{ translateX: capsuleX }],
  } as unknown as StyleProp<ViewStyle>;
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
  const selectedFillStyle = {
    opacity: selectedFillOpacity,
  } as unknown as StyleProp<ViewStyle>;
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
    shellScale.stopAnimation();
    if (reduceMotion) {
      shellScale.setValue(1);
      return;
    }

    ReactNativeAnimated.timing(shellScale, {
      toValue: 1,
      duration: shellMotion.releaseDuration,
      easing: Easing.out(Easing.cubic),
      useNativeDriver: false,
    }).start();
  }, [
    reduceMotion,
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

    const pressAttempt = pressAttemptRef.current;
    if (
      pressAttempt.destination === destination
      && !pressAttempt.navigationCommitted
    ) {
      const settlingState: NavigationCapsuleState = {
        ...transitionRef.current,
        phase: 'settling',
      };
      transitionRef.current = settlingState;
      setMotionState(settlingState);
      return;
    }

    const settledState = settleBottomNavigationTransition(transitionRef.current);
    transitionRef.current = settledState;
    setMotionState(settledState);
    setOutgoingLabel(null);

    if (reduceMotion) {
      selectedFillOpacity.setValue(1);
      shellScale.setValue(1);
      return;
    }

    selectedFillOpacity.stopAnimation();
    ReactNativeAnimated.timing(selectedFillOpacity, {
      toValue: 1,
      duration: surfaceTimeline.fillRestoreDuration,
      easing: Easing.bezier(0.23, 1, 0.32, 1),
      useNativeDriver: true,
    }).start();
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
        easing: Easing.out(Easing.cubic),
        useNativeDriver: true,
      }),
      ReactNativeAnimated.timing(selectedLabelScale, {
        toValue: 1,
        duration: labelMotion.duration,
        easing: Easing.out(Easing.cubic),
        useNativeDriver: true,
      }),
      ReactNativeAnimated.timing(selectedLabelTranslateX, {
        toValue: 0,
        duration: labelMotion.duration,
        easing: Easing.out(Easing.cubic),
        useNativeDriver: true,
      }),
      ReactNativeAnimated.timing(outgoingLabelOpacity, {
        toValue: 0,
        duration: labelMotion.duration,
        easing: Easing.out(Easing.cubic),
        useNativeDriver: true,
      }),
      ReactNativeAnimated.timing(outgoingLabelScale, {
        toValue: labelMotion.enterScale,
        duration: labelMotion.duration,
        easing: Easing.out(Easing.cubic),
        useNativeDriver: true,
      }),
      ReactNativeAnimated.timing(outgoingLabelTranslateX, {
        toValue: labelMotion.enterTranslateX,
        duration: labelMotion.duration,
        easing: Easing.out(Easing.cubic),
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
    const nextDestinationOffsets = getBottomNavigationDestinationOffsets(destination);
    startSelectedContentMotion(destination, sequence);

    if (reduceMotion) {
      capsuleX.stopAnimation();
      capsuleWidth.stopAnimation();
      shellWidth.stopAnimation();
      destinationOffsets.forEach((offset) => offset.stopAnimation());
      selectedFillOpacity.stopAnimation();
      capsuleX.setValue(centerOffset);
      capsuleWidth.setValue(frame.width);
      shellWidth.setValue(frame.shellWidth);
      destinationOffsets.forEach((offset, index) => {
        offset.setValue(nextDestinationOffsets[index]);
      });
      shellScale.setValue(1);
      ReactNativeAnimated.sequence([
        ReactNativeAnimated.timing(selectedFillOpacity, {
          toValue: 0,
          duration: reducedMotion.crossfadeDuration / 2,
          useNativeDriver: true,
        }),
        ReactNativeAnimated.timing(selectedFillOpacity, {
          toValue: 1,
          duration: reducedMotion.crossfadeDuration / 2,
          useNativeDriver: true,
        }),
      ]).start();
      return;
    }

    capsuleX.stopAnimation();
    capsuleWidth.stopAnimation();
    shellWidth.stopAnimation();
    const coordinatedSpring = {
      stiffness: capsuleMotion.stiffness,
      damping: capsuleMotion.damping,
      mass: capsuleMotion.mass,
      overshootClamping: false,
      restDisplacementThreshold: 0.1,
      restSpeedThreshold: 0.1,
      useNativeDriver: false,
    };
    ReactNativeAnimated.parallel([
      ReactNativeAnimated.spring(capsuleX, {
        toValue: centerOffset,
        ...coordinatedSpring,
      }),
      ReactNativeAnimated.spring(capsuleWidth, {
        toValue: frame.width,
        ...coordinatedSpring,
      }),
      ReactNativeAnimated.spring(shellWidth, {
        toValue: frame.shellWidth,
        ...coordinatedSpring,
      }),
      ...destinationOffsets.map((offset, index) => ReactNativeAnimated.spring(offset, {
        toValue: nextDestinationOffsets[index],
        ...coordinatedSpring,
      })),
    ]).start(({ finished }) => {
      if (finished) finishCapsuleTransition(destination, sequence);
    });
  }, [
    capsuleMotion.damping,
    capsuleMotion.mass,
    capsuleMotion.stiffness,
    capsuleWidth,
    capsuleX,
    destinationOffsets,
    finishCapsuleTransition,
    reduceMotion,
    reducedMotion.crossfadeDuration,
    selectedFillOpacity,
    shellScale,
    shellWidth,
    startSelectedContentMotion,
  ]);

  const handleNavigationPressIn = useCallback((item: BottomNavigationItem) => {
    if (cancelledPressTimerRef.current) {
      clearTimeout(cancelledPressTimerRef.current);
      cancelledPressTimerRef.current = null;
    }

    const pressSequence = pressAttemptRef.current.sequence + 1;
    pressAttemptRef.current = {
      sequence: pressSequence,
      navigationCommitted: false,
      origin: activeId,
      destination: item.id,
    };
    shellScale.stopAnimation();
    if (reduceMotion) {
      shellScale.setValue(1);
    } else {
      ReactNativeAnimated.timing(shellScale, {
        toValue: shellMotion.pressedScale,
        duration: shellMotion.pressDuration,
        easing: Easing.in(Easing.cubic),
        useNativeDriver: false,
      }).start();
    }

    if (transitionRef.current.to === item.id) {
      return;
    }

    const previousItem = BOTTOM_NAVIGATION_ITEMS.find(
      (destination) => destination.id === transitionRef.current.to,
    );
    const nextState = startBottomNavigationTransition(transitionRef.current, item.id);
    setOutgoingLabel(previousItem?.label ?? null);
    transitionRef.current = nextState;
    setMotionState(nextState);

    const transitionSequence = transitionSequenceRef.current + 1;
    transitionSequenceRef.current = transitionSequence;
    latestTransitionRef.current = { destination: item.id, sequence: transitionSequence };

    selectedFillOpacity.stopAnimation();
    ReactNativeAnimated.timing(selectedFillOpacity, {
      toValue: 0,
      duration: reduceMotion
        ? reducedMotion.crossfadeDuration / 2
        : surfaceTimeline.fillFadeOutDuration,
      easing: Easing.bezier(0.23, 1, 0.32, 1),
      useNativeDriver: true,
    }).start();
    startCapsuleTransition(item.id, transitionSequence);
  }, [
    activeId,
    reduceMotion,
    reducedMotion.crossfadeDuration,
    selectedFillOpacity,
    shellMotion.pressDuration,
    shellMotion.pressedScale,
    shellScale,
    startCapsuleTransition,
    surfaceTimeline,
  ]);

  const cancelNavigationPreview = useCallback(() => {
    const attempt = pressAttemptRef.current;
    if (attempt.navigationCommitted || !attempt.destination) return;

    const origin = attempt.origin;
    const frame = getBottomNavigationCapsuleFrame(origin);
    const originDestinationOffsets = getBottomNavigationDestinationOffsets(origin);
    const restingState: NavigationCapsuleState = {
      from: origin,
      to: origin,
      phase: 'resting',
    };
    transitionSequenceRef.current += 1;
    latestTransitionRef.current = {
      destination: origin,
      sequence: transitionSequenceRef.current,
    };
    pressAttemptRef.current = {
      ...attempt,
      destination: null,
    };
    transitionRef.current = restingState;
    setMotionState(restingState);
    setOutgoingLabel(null);

    capsuleX.stopAnimation();
    capsuleWidth.stopAnimation();
    shellWidth.stopAnimation();
    destinationOffsets.forEach((offset) => offset.stopAnimation());
    selectedFillOpacity.stopAnimation();
    stopSelectedContentMotion();
    const returnSpring = {
      stiffness: capsuleMotion.stiffness,
      damping: capsuleMotion.damping,
      mass: capsuleMotion.mass,
      useNativeDriver: false,
    };
    ReactNativeAnimated.parallel([
      ReactNativeAnimated.spring(capsuleX, {
        toValue: getBottomNavigationCapsuleCenterOffset(origin),
        ...returnSpring,
      }),
      ReactNativeAnimated.spring(capsuleWidth, {
        toValue: frame.width,
        ...returnSpring,
      }),
      ReactNativeAnimated.spring(shellWidth, {
        toValue: frame.shellWidth,
        ...returnSpring,
      }),
      ...destinationOffsets.map((offset, index) => ReactNativeAnimated.spring(offset, {
        toValue: originDestinationOffsets[index],
        ...returnSpring,
      })),
    ]).start();
    selectedContentOpacity.setValue(1);
    selectedLabelOpacity.setValue(1);
    selectedLabelScale.setValue(1);
    selectedLabelTranslateX.setValue(0);
    outgoingLabelOpacity.setValue(0);
    selectedFillOpacity.setValue(1);
    releaseShell();
  }, [
    capsuleMotion.damping,
    capsuleMotion.mass,
    capsuleMotion.stiffness,
    capsuleWidth,
    capsuleX,
    destinationOffsets,
    outgoingLabelOpacity,
    releaseShell,
    selectedContentOpacity,
    selectedFillOpacity,
    selectedLabelOpacity,
    selectedLabelScale,
    selectedLabelTranslateX,
    shellWidth,
    stopSelectedContentMotion,
  ]);

  const handleNavigationPressOut = useCallback(() => {
    const pressSequence = pressAttemptRef.current.sequence;
    cancelledPressTimerRef.current = setTimeout(() => {
      cancelledPressTimerRef.current = null;
      if (!mountedRef.current) return;
      if (pressAttemptRef.current.sequence !== pressSequence) return;
      if (pressAttemptRef.current.navigationCommitted) return;
      cancelNavigationPreview();
    }, 0);
  }, [cancelNavigationPreview]);

  const navigateTo = useCallback((item: BottomNavigationItem) => {
    pressAttemptRef.current.navigationCommitted = true;
    router.navigate(item.path as never);
    if (transitionRef.current.phase === 'settling') {
      finishCapsuleTransition(item.id, latestTransitionRef.current.sequence);
    } else if (transitionRef.current.phase === 'resting') {
      releaseShell();
    }
  }, [
    finishCapsuleTransition,
    releaseShell,
  ]);

  useEffect(() => {
    let active = true;
    AccessibilityInfo.isReduceMotionEnabled().then((enabled) => {
      if (active) setReduceMotion(enabled);
    });
    const subscription = AccessibilityInfo.addEventListener(
      'reduceMotionChanged',
      setReduceMotion,
    );

    return () => {
      active = false;
      subscription.remove();
    };
  }, []);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      if (cancelledPressTimerRef.current) {
        clearTimeout(cancelledPressTimerRef.current);
        cancelledPressTimerRef.current = null;
      }
      stopSelectedContentMotion();
      shellScale.stopAnimation();
      capsuleX.stopAnimation();
      capsuleWidth.stopAnimation();
      shellWidth.stopAnimation();
      destinationOffsets.forEach((offset) => offset.stopAnimation());
      selectedFillOpacity.stopAnimation();
    };
  }, [
    capsuleWidth,
    capsuleX,
    destinationOffsets,
    selectedFillOpacity,
    shellScale,
    shellWidth,
    stopSelectedContentMotion,
  ]);

  useEffect(() => {
    if (transitionRef.current.to === activeId) return;
    if (
      !pressAttemptRef.current.navigationCommitted
      && pressAttemptRef.current.destination === transitionRef.current.to
    ) return;

    const frame = getBottomNavigationCapsuleFrame(activeId);
    const activeDestinationOffsets = getBottomNavigationDestinationOffsets(activeId);
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
    capsuleX.stopAnimation();
    capsuleWidth.stopAnimation();
    shellWidth.stopAnimation();
    destinationOffsets.forEach((offset) => offset.stopAnimation());
    selectedFillOpacity.stopAnimation();
    capsuleX.setValue(getBottomNavigationCapsuleCenterOffset(activeId));
    capsuleWidth.setValue(frame.width);
    shellWidth.setValue(frame.shellWidth);
    destinationOffsets.forEach((offset, index) => {
      offset.setValue(activeDestinationOffsets[index]);
    });
    selectedFillOpacity.setValue(1);
    shellScale.setValue(1);
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
    destinationOffsets,
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
        <ReactNativeAnimated.View
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
                position: 'relative',
              }}
            >
              {BOTTOM_NAVIGATION_ITEMS.map((item, index) => (
                <NavigationDestination
                  key={item.id}
                  item={item}
                  selected={item.id === motionState.to}
                  visualHidden={
                    item.id === renderPolicy.hiddenStableDestination
                    || (motionState.phase !== 'resting' && item.id === motionState.from)
                  }
                  centerOffset={destinationOffsets[index]}
                  userId={userId}
                  onPress={() => navigateTo(item)}
                  onPressIn={() => handleNavigationPressIn(item)}
                  onPressOut={handleNavigationPressOut}
                />
              ))}
            </View>

            <ReactNativeAnimated.View
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
            </ReactNativeAnimated.View>
          </NavigationMaterial>
        </ReactNativeAnimated.View>
      </View>
    </View>
  );
}

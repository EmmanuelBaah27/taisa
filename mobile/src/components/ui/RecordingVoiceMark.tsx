import { useEffect, useRef, useState } from 'react';
import { AccessibilityInfo, Animated, Easing, View } from 'react-native';
import Svg, { Circle, Path } from 'react-native-svg';

import { colors } from '../../constants/theme';

export const RECORDING_VOICE_MARK_PATHS = {
  left: 'M24.4282 26.8479C17.9055 28.4497 10.1559 16.8666 4.66667 16.8666',
  right: 'M7.13333 24.4666C15.1614 24.4666 20.3298 14.3333 28.3298 14.3333',
} as const;

export const RECORDING_VOICE_MARK_MOTION = {
  duration: 2000,
  loop: true,
  easing: [0.37, 0, 0.63, 1],
  keyframes: [
    { duration: 190, left: -5, right: 5 },
    { duration: 250, left: 5, right: -5 },
    { duration: 250, left: -3.5, right: 3.5 },
    { duration: 250, left: 3.5, right: -3.5 },
    { duration: 250, left: -1.5, right: 1.5 },
    { duration: 250, left: 1, right: -1 },
    { duration: 60, left: 0, right: 0 },
  ],
  restDuration: 500,
} as const;

function voiceWaveSequence(value: Animated.Value, side: 'left' | 'right') {
  const easing = Easing.bezier(...RECORDING_VOICE_MARK_MOTION.easing);
  return Animated.sequence([
    ...RECORDING_VOICE_MARK_MOTION.keyframes.map((frame) => Animated.timing(value, {
      toValue: frame[side],
      duration: frame.duration,
      easing,
      useNativeDriver: true,
    })),
    Animated.delay(RECORDING_VOICE_MARK_MOTION.restDuration),
  ]);
}

export function RecordingVoiceMark() {
  const leftY = useRef(new Animated.Value(0)).current;
  const rightY = useRef(new Animated.Value(0)).current;
  const [reduceMotion, setReduceMotion] = useState(false);

  useEffect(() => {
    let mounted = true;
    AccessibilityInfo.isReduceMotionEnabled().then((enabled) => {
      if (mounted) setReduceMotion(enabled);
    });
    const subscription = AccessibilityInfo.addEventListener('reduceMotionChanged', setReduceMotion);
    return () => {
      mounted = false;
      subscription.remove();
    };
  }, []);

  useEffect(() => {
    leftY.stopAnimation();
    rightY.stopAnimation();
    leftY.setValue(0);
    rightY.setValue(0);
    if (reduceMotion) return;

    const animation = Animated.parallel([
      Animated.loop(voiceWaveSequence(leftY, 'left')),
      Animated.loop(voiceWaveSequence(rightY, 'right')),
    ]);
    animation.start();
    return () => animation.stop();
  }, [leftY, reduceMotion, rightY]);

  return (
    <View accessibilityElementsHidden importantForAccessibility="no-hide-descendants" className="relative h-8 w-8">
      <Svg width={32} height={32} viewBox="0 0 32 32" className="absolute">
        <Circle cx={16} cy={16} r={12.3333} fill="none" stroke={colors.recordingMark} strokeWidth={2} />
      </Svg>
      <Animated.View className="absolute inset-0" style={{ transform: [{ translateY: leftY }] }}>
        <Svg width={32} height={32} viewBox="0 0 32 32">
          <Path d={RECORDING_VOICE_MARK_PATHS.left} fill="none" stroke={colors.recordingMark} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />
        </Svg>
      </Animated.View>
      <Animated.View className="absolute inset-0" style={{ transform: [{ translateY: rightY }] }}>
        <Svg width={32} height={32} viewBox="0 0 32 32">
          <Path d={RECORDING_VOICE_MARK_PATHS.right} fill="none" stroke={colors.recordingMark} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />
        </Svg>
      </Animated.View>
    </View>
  );
}

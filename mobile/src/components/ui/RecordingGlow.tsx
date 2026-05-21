import { useEffect, useRef } from 'react';
import { Animated, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';

export interface RecordingGlowProps {
  amplitude: number; // 0–10
}

export function RecordingGlow({ amplitude }: RecordingGlowProps) {
  const animValue = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    Animated.timing(animValue, {
      toValue: amplitude,
      duration: 120,
      useNativeDriver: true,
    }).start();
  }, [amplitude]);

  const scale = animValue.interpolate({
    inputRange: [0, 10],
    outputRange: [1, 1.8],
    extrapolate: 'clamp',
  });

  const opacity = animValue.interpolate({
    inputRange: [0, 10],
    outputRange: [0.06, 0.55],
    extrapolate: 'clamp',
  });

  return (
    <View
      style={{
        position: 'absolute',
        bottom: 0,
        left: 0,
        right: 0,
        height: 200,
        overflow: 'hidden',
        pointerEvents: 'none',
      }}
    >
      <Animated.View
        style={{
          position: 'absolute',
          bottom: -180,
          alignSelf: 'center',
          width: 400,
          height: 400,
          borderRadius: 200,
          overflow: 'hidden',
          transform: [{ scale }],
          opacity,
        }}
      >
        <LinearGradient
          colors={['#cdec1a', '#cdec1a99', 'transparent']}
          locations={[0, 0.45, 1]}
          start={{ x: 0.5, y: 1 }}
          end={{ x: 0.5, y: 0 }}
          style={{ flex: 1 }}
        />
      </Animated.View>
    </View>
  );
}

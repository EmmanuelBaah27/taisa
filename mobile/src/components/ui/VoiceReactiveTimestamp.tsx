import { useEffect } from 'react';
import { Text, View } from 'react-native';
import { Canvas, Fill, Shader, Skia } from '@shopify/react-native-skia';
import {
  Easing,
  useAnimatedReaction,
  useDerivedValue,
  useSharedValue,
  withRepeat,
  withTiming,
  type SharedValue,
} from 'react-native-reanimated';

export const VOICE_REACTIVE_TIMESTAMP = {
  width: 60,
  height: 56,
  duration: 2000,
  noiseGate: 0.05,
  attack: 90,
  release: 220,
  peaks: [0.35, 0.5, 0.65],
} as const;

const EFFECT = Skia.RuntimeEffect.Make(`
uniform float2 iResolution;
uniform float iPhase;
uniform float iEnergy;

float pulse(float phase, float peak) {
  float before = smoothstep(0.0, peak, phase);
  float after = 1.0 - smoothstep(peak, 1.0, phase);
  return min(before, after);
}

half4 main(float2 fragCoord) {
  float2 uv = fragCoord / iResolution;
  float energy = clamp((iEnergy - 0.05) / 0.45, 0.0, 1.0);
  float p1 = pulse(iPhase, 0.35) * energy;
  float p2 = pulse(iPhase, 0.50) * energy;
  float p3 = pulse(iPhase, 0.65) * energy;

  float3 base1 = float3(0.992, 0.902, 0.541);
  float3 base2 = float3(0.796, 0.682, 1.000);
  float3 base3 = float3(0.678, 0.922, 0.710);
  float3 hot1 = float3(0.980, 0.749, 0.141);
  float3 hot2 = float3(0.659, 0.482, 0.961);
  float3 hot3 = float3(0.314, 0.816, 0.380);

  float spread1 = mix(0.18, 0.25, p1);
  float spread2 = mix(0.22, 0.32, p2);
  float spread3 = mix(0.19, 0.27, p3);
  float g1 = exp(-distance(uv, float2(0.17, 0.53)) * distance(uv, float2(0.17, 0.53)) / spread1);
  float g2 = exp(-distance(uv, float2(0.50, 0.50)) * distance(uv, float2(0.50, 0.50)) / spread2);
  float g3 = exp(-distance(uv, float2(0.83, 0.52)) * distance(uv, float2(0.83, 0.52)) / spread3);

  float3 color = mix(base1, hot1, p1) * g1
    + mix(base2, hot2, p2) * g2
    + mix(base3, hot3, p3) * g3;
  float alpha = clamp((g1 + g2 + g3) * mix(0.14, 0.28, energy), 0.0, 0.55);
  return half4(half3(clamp(color / max(g1 + g2 + g3, 1.0), 0.0, 1.0)), half(alpha));
}
`);

function formatDuration(seconds: number): string {
  const whole = Math.max(0, Math.floor(seconds));
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`;
}

export interface VoiceReactiveTimestampProps {
  durationSeconds: number;
  amplitude: SharedValue<number>;
  paused: boolean;
}

export function VoiceReactiveTimestamp({
  durationSeconds,
  amplitude,
  paused,
}: VoiceReactiveTimestampProps) {
  const phase = useSharedValue(0);
  const energy = useSharedValue(0);

  useEffect(() => {
    phase.value = withRepeat(
      withTiming(1, { duration: VOICE_REACTIVE_TIMESTAMP.duration, easing: Easing.linear }),
      -1,
      false,
    );
  }, [phase]);

  useAnimatedReaction(
    () => paused ? 0 : amplitude.value,
    (next, previous) => {
      energy.value = withTiming(next, {
        duration: next > (previous ?? 0)
          ? VOICE_REACTIVE_TIMESTAMP.attack
          : VOICE_REACTIVE_TIMESTAMP.release,
        easing: Easing.out(Easing.cubic),
      });
    },
    [paused],
  );

  const uniforms = useDerivedValue(() => ({
    iResolution: [VOICE_REACTIVE_TIMESTAMP.width, VOICE_REACTIVE_TIMESTAMP.height],
    iPhase: phase.value,
    iEnergy: energy.value,
  }));

  return (
    <View className="relative h-14 w-[60px] items-center justify-center">
      {EFFECT ? (
        <Canvas
          style={{
            position: 'absolute',
            top: 0,
            left: 0,
            width: VOICE_REACTIVE_TIMESTAMP.width,
            height: VOICE_REACTIVE_TIMESTAMP.height,
            pointerEvents: 'none',
            zIndex: 0,
          }}
        >
          <Fill><Shader source={EFFECT} uniforms={uniforms} /></Fill>
        </Canvas>
      ) : null}
      <Text className="text-muted-foreground text-small-regular" style={{ zIndex: 1 }}>
        {formatDuration(durationSeconds)}
      </Text>
    </View>
  );
}

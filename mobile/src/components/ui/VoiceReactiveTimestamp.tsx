import { Text, View } from 'react-native';
import { Canvas, Fill, Shader, Skia } from '@shopify/react-native-skia';
import {
  useDerivedValue,
  type SharedValue,
} from 'react-native-reanimated';

export const VOICE_REACTIVE_TIMESTAMP = {
  width: 60,
  height: 56,
  canvasWidth: 180,
  canvasHeight: 112,
  rawAmplitude: true,
} as const;

const EFFECT = Skia.RuntimeEffect.Make(`
uniform float2 iResolution;
uniform float iEnergy;

half4 main(float2 fragCoord) {
  float2 uv = fragCoord / iResolution;
  float energy = clamp(iEnergy, 0.0, 1.0);

  float3 base1 = float3(0.992, 0.902, 0.541);
  float3 base2 = float3(0.796, 0.682, 1.000);
  float3 base3 = float3(0.678, 0.922, 0.710);
  float3 hot1 = float3(0.980, 0.749, 0.141);
  float3 hot2 = float3(0.659, 0.482, 0.961);
  float3 hot3 = float3(0.314, 0.816, 0.380);

  float spread = mix(0.045, 0.095, energy);
  float g1 = exp(-dot(uv - float2(0.35, 0.53), uv - float2(0.35, 0.53)) / spread);
  float g2 = exp(-dot(uv - float2(0.50, 0.50), uv - float2(0.50, 0.50)) / (spread * 1.15));
  float g3 = exp(-dot(uv - float2(0.65, 0.52), uv - float2(0.65, 0.52)) / spread);

  float3 color = mix(base1, hot1, energy) * g1
    + mix(base2, hot2, energy) * g2
    + mix(base3, hot3, energy) * g3;
  float edgeX = smoothstep(0.0, 0.18, uv.x) * (1.0 - smoothstep(0.82, 1.0, uv.x));
  float edgeY = smoothstep(0.0, 0.20, uv.y) * (1.0 - smoothstep(0.80, 1.0, uv.y));
  float alpha = clamp((g1 + g2 + g3) * mix(0.10, 0.32, energy), 0.0, 0.58) * edgeX * edgeY;
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
  const uniforms = useDerivedValue(() => ({
    iResolution: [VOICE_REACTIVE_TIMESTAMP.canvasWidth, VOICE_REACTIVE_TIMESTAMP.canvasHeight],
    iEnergy: paused ? 0 : amplitude.value,
  }), [paused]);

  return (
    <View className="relative h-14 w-[60px] items-center justify-center">
      {EFFECT ? (
        <Canvas
          style={{
            position: 'absolute',
            top: (VOICE_REACTIVE_TIMESTAMP.height - VOICE_REACTIVE_TIMESTAMP.canvasHeight) / 2,
            left: (VOICE_REACTIVE_TIMESTAMP.width - VOICE_REACTIVE_TIMESTAMP.canvasWidth) / 2,
            width: VOICE_REACTIVE_TIMESTAMP.canvasWidth,
            height: VOICE_REACTIVE_TIMESTAMP.canvasHeight,
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

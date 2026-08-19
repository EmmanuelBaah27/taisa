import { Text, View } from 'react-native';
import { Canvas, Fill, Shader, Skia } from '@shopify/react-native-skia';

export const VOICE_REACTIVE_TIMESTAMP = {
  width: 60,
  height: 56,
  canvasWidth: 120,
  canvasHeight: 80,
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
  float spread = mix(0.020, 0.052, energy);
  float g1 = exp(-dot(uv - float2(0.28, 0.53), uv - float2(0.28, 0.53)) / spread);
  float g2 = exp(-dot(uv - float2(0.50, 0.50), uv - float2(0.50, 0.50)) / (spread * 1.15));
  float g3 = exp(-dot(uv - float2(0.72, 0.52), uv - float2(0.72, 0.52)) / spread);

  float purple = g2 * 1.45;
  float3 color = base1 * g1 + base2 * purple + base3 * g3;
  float edgeX = smoothstep(0.0, 0.24, uv.x) * (1.0 - smoothstep(0.76, 1.0, uv.x));
  float edgeY = smoothstep(0.0, 0.26, uv.y) * (1.0 - smoothstep(0.74, 1.0, uv.y));
  float glow = g1 + purple + g3;
  float alpha = clamp(glow * (0.28 * energy), 0.0, 0.46) * edgeX * edgeY;
  float3 finalColor = clamp(color / max(glow, 0.0001), 0.0, 1.0);
  return half4(half3(finalColor * alpha), half(alpha));
}
`);

function formatDuration(seconds: number): string {
  const whole = Math.max(0, Math.floor(seconds));
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`;
}

export interface VoiceReactiveTimestampProps {
  durationSeconds: number;
  amplitudeLevel: number;
  paused: boolean;
}

export function VoiceReactiveTimestamp({
  durationSeconds,
  amplitudeLevel,
  paused,
}: VoiceReactiveTimestampProps) {
  const uniforms = {
    iResolution: [VOICE_REACTIVE_TIMESTAMP.canvasWidth, VOICE_REACTIVE_TIMESTAMP.canvasHeight],
    iEnergy: paused ? 0 : amplitudeLevel,
  };

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

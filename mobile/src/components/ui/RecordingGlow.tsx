import { useEffect } from 'react';
import { useWindowDimensions } from 'react-native';
import { Canvas, Fill, Shader, Skia } from '@shopify/react-native-skia';
import {
  useSharedValue,
  useDerivedValue,
  withRepeat,
  withTiming,
  Easing,
} from 'react-native-reanimated';
import type { SharedValue } from 'react-native-reanimated';

const GLOW_HEIGHT_RATIO = 0.28;

// Two soft aurora blobs (lime left, peach right) matching the Figma design.
// Blob centres sit below the canvas so only the soft upper edge is visible.
// iDither adds hash-based grain; iColorCount gates which blobs render (1=lime, 2=+peach, 3=+violet).
const SHADER_SRC = Skia.RuntimeEffect.Make(`
uniform float2 iResolution;
uniform float  iTime;
uniform float  iAmplitude;
uniform float  iDither;
uniform float  iColorCount;

float hash(float2 p) {
  return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}

half4 main(float2 fragCoord) {
  float2 uv  = fragCoord / iResolution;
  float  amp = iAmplitude;

  float breath = 1.0 + 0.08 * sin(iTime * 1.4) + amp * 0.20;

  // Lime blob — always active
  float2 lOff = uv - float2(0.05, 1.30);
  float  lime = exp(-dot(lOff * float2(0.80, 0.50), lOff * float2(0.80, 0.50)) * 3.2 / breath);

  // Peach blob — active when iColorCount >= 2
  float peach = 0.0;
  if (iColorCount >= 2.0) {
    float2 pOff = uv - float2(0.95, 1.30);
    peach = exp(-dot(pOff * float2(0.80, 0.50), pOff * float2(0.80, 0.50)) * 3.2 / breath);
  }

  // Violet blob — active when iColorCount >= 3
  float violet = 0.0;
  if (iColorCount >= 3.0) {
    float2 vOff = uv - float2(0.50, 1.20);
    violet = exp(-dot(vOff * float2(0.90, 0.50), vOff * float2(0.90, 0.50)) * 3.2 / breath);
  }

  float3 limeCol   = float3(0.776, 0.922, 0.322);
  float3 peachCol  = float3(0.980, 0.714, 0.573);
  float3 violetCol = float3(0.600, 0.400, 0.900);

  float3 premul = lime * limeCol + peach * peachCol + violet * violetCol;
  float  alpha  = clamp(lime + peach + violet, 0.0, 1.0);

  float fade = smoothstep(0.0, 0.70, uv.y);
  premul *= fade;
  alpha  *= fade;

  // Dither: subtle hash noise layered over final color
  float noise = hash(fragCoord) * iDither * 0.08;
  premul = clamp(premul + float3(noise), float3(0.0), float3(1.0));

  return half4(half3(premul), half(alpha));
}
`);

export interface RecordingGlowProps {
  amplitude: SharedValue<number>;
  ditherIntensity?: SharedValue<number>;
  colorCount?: SharedValue<number>;
  visible?: boolean;
}

export function RecordingGlow({
  amplitude,
  ditherIntensity,
  colorCount,
  visible = true,
}: RecordingGlowProps) {
  const { width, height } = useWindowDimensions();
  const glowH = Math.round(height * GLOW_HEIGHT_RATIO);
  const iTime = useSharedValue(0);
  const fallbackDither = useSharedValue(0);
  const fallbackColorCount = useSharedValue(2);

  useEffect(() => {
    iTime.value = withRepeat(
      withTiming(3600, { duration: 3_600_000, easing: Easing.linear }),
      -1,
      false
    );
  }, []);

  const uniforms = useDerivedValue(() => ({
    iResolution: [width, glowH],
    iTime: iTime.value,
    iAmplitude: amplitude.value,
    iDither: (ditherIntensity ?? fallbackDither).value,
    iColorCount: (colorCount ?? fallbackColorCount).value,
  }));

  if (!SHADER_SRC || !visible) return null;

  return (
    <Canvas
      style={{
        position: 'absolute',
        bottom: 0,
        left: 0,
        width,
        height: glowH,
        pointerEvents: 'none',
      }}
    >
      <Fill>
        <Shader source={SHADER_SRC} uniforms={uniforms} />
      </Fill>
    </Canvas>
  );
}

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

// Re-derives the glow color analytically at a refracted UV — no inter-canvas texture reads.
// Each cell of iCubeSize pixels acts as a convex glass lens that bends the glow underneath.
const CUBE_SHADER_SRC = Skia.RuntimeEffect.Make(`
uniform float2 iResolution;
uniform float  iTime;
uniform float  iAmplitude;
uniform float  iCubeSize;

float3 glowAt(float2 uv, float amp, float t) {
  float breath = 1.0 + 0.08 * sin(t * 1.4) + amp * 0.20;

  float2 lOff = uv - float2(0.05, 1.30);
  float  lime = exp(-dot(lOff * float2(0.80, 0.50), lOff * float2(0.80, 0.50)) * 3.2 / breath);

  float2 pOff = uv - float2(0.95, 1.30);
  float  peach = exp(-dot(pOff * float2(0.80, 0.50), pOff * float2(0.80, 0.50)) * 3.2 / breath);

  float3 limeCol  = float3(0.776, 0.922, 0.322);
  float3 peachCol = float3(0.980, 0.714, 0.573);
  return lime * limeCol + peach * peachCol;
}

half4 main(float2 fragCoord) {
  float2 uv = fragCoord / iResolution;
  float  cs = iCubeSize;

  float2 cellIdx    = floor(fragCoord / cs);
  float2 cellUV     = fract(fragCoord / cs);          // 0..1 within cell
  float2 cellCenter = (cellIdx + 0.5) * cs;

  // Convex lens: offset bends inward toward cell edges
  float2 offset = (fragCoord - cellCenter) / cs;
  float2 refractedUV = uv + offset * 0.14 * (1.0 - length(offset) * 1.8);
  refractedUV = clamp(refractedUV, float2(0.001), float2(0.999));

  float3 color = glowAt(refractedUV, iAmplitude, iTime);

  float fade  = smoothstep(0.0, 0.70, uv.y);
  float alpha = clamp((color.r + color.g + color.b) * 1.2, 0.0, 1.0) * fade;

  // Glass facet edge highlight at cell borders
  float edgeDist = min(min(cellUV.x, 1.0 - cellUV.x), min(cellUV.y, 1.0 - cellUV.y));
  float edge = 1.0 - smoothstep(0.0, 0.07, edgeDist);
  color += float3(edge * 0.18 * fade);
  alpha  = clamp(alpha + edge * 0.12 * fade, 0.0, 1.0);

  return half4(half3(color), half(alpha));
}
`);

export interface CubeRefractionOverlayProps {
  amplitude: SharedValue<number>;
  cubeSize: SharedValue<number>;
}

export function CubeRefractionOverlay({ amplitude, cubeSize }: CubeRefractionOverlayProps) {
  const { width, height } = useWindowDimensions();
  const glowH = Math.round(height * GLOW_HEIGHT_RATIO);
  const iTime = useSharedValue(0);

  useEffect(() => {
    iTime.value = withRepeat(
      withTiming(3600, { duration: 3_600_000, easing: Easing.linear }),
      -1,
      false
    );
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const uniforms = useDerivedValue(() => ({
    iResolution: [width, glowH],
    iTime: iTime.value,
    iAmplitude: amplitude.value,
    iCubeSize: cubeSize.value,
  }));

  if (!CUBE_SHADER_SRC) return null;

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
        <Shader source={CUBE_SHADER_SRC} uniforms={uniforms} />
      </Fill>
    </Canvas>
  );
}

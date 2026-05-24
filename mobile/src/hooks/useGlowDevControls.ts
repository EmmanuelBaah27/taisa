// mobile/src/hooks/useGlowDevControls.ts
import { useState } from 'react';
import { useSharedValue, useDerivedValue } from 'react-native-reanimated';
import type { SharedValue } from 'react-native-reanimated';

export interface GlowDevValues {
  minAmplitude: number;
  maxAmplitude: number;
  ditherIntensity: number;
  colorCount: 1 | 2 | 3;
  cubeEnabled: boolean;
  cubeSize: number;
}

export interface GlowDevSetters {
  setMinAmplitude: (v: number) => void;
  setMaxAmplitude: (v: number) => void;
  setDitherIntensity: (v: number) => void;
  setColorCount: (v: 1 | 2 | 3) => void;
  setCubeEnabled: (v: boolean) => void;
  setCubeSize: (v: number) => void;
}

export interface GlowDevSharedValues {
  effectiveAmplitude: SharedValue<number>;
  ditherSV: SharedValue<number>;
  colorCountSV: SharedValue<number>;
  cubeSizeSV: SharedValue<number>;
}

export type GlowDevControls = GlowDevValues & GlowDevSetters & GlowDevSharedValues;

export function useGlowDevControls(audioAmplitude: SharedValue<number>): GlowDevControls {
  const [minAmplitude, setMinAmplitudeState] = useState(0.0);
  const [maxAmplitude, setMaxAmplitudeState] = useState(1.0);
  const [ditherIntensity, setDitherIntensityState] = useState(0.0);
  const [colorCount, setColorCountState] = useState<1 | 2 | 3>(2);
  const [cubeEnabled, setCubeEnabled] = useState(false);
  const [cubeSize, setCubeSizeState] = useState(24);

  const minSV = useSharedValue(0.0);
  const maxSV = useSharedValue(1.0);
  const ditherSV = useSharedValue(0.0);
  const colorCountSV = useSharedValue(2);
  const cubeSizeSV = useSharedValue(24);

  const effectiveAmplitude = useDerivedValue(() =>
    minSV.value + audioAmplitude.value * (maxSV.value - minSV.value)
  );

  return {
    minAmplitude,
    maxAmplitude,
    ditherIntensity,
    colorCount,
    cubeEnabled,
    cubeSize,
    setMinAmplitude: (v) => { setMinAmplitudeState(v); minSV.value = v; },
    setMaxAmplitude: (v) => { setMaxAmplitudeState(v); maxSV.value = v; },
    setDitherIntensity: (v) => { setDitherIntensityState(v); ditherSV.value = v; },
    setColorCount: (v) => { setColorCountState(v); colorCountSV.value = v; },
    setCubeEnabled,
    setCubeSize: (v) => { setCubeSizeState(v); cubeSizeSV.value = v; },
    effectiveAmplitude,
    ditherSV,
    colorCountSV,
    cubeSizeSV,
  };
}

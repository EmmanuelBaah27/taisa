// mobile/src/hooks/useGlowDevControls.ts
import { useState, useCallback } from 'react';
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

const DEFAULT_CUBE_SIZE = 24;

export function useGlowDevControls(audioAmplitude: SharedValue<number>): GlowDevControls {
  const [minAmplitude, setMinAmplitudeState] = useState(0.0);
  const [maxAmplitude, setMaxAmplitudeState] = useState(1.0);
  const [ditherIntensity, setDitherIntensityState] = useState(0.0);
  const [colorCount, setColorCountState] = useState<1 | 2 | 3>(2);
  const [cubeEnabled, setCubeEnabled] = useState(false);
  const [cubeSize, setCubeSizeState] = useState(DEFAULT_CUBE_SIZE);

  const minSV = useSharedValue(0.0);
  const maxSV = useSharedValue(1.0);
  const ditherSV = useSharedValue(0.0);
  const colorCountSV = useSharedValue(2);
  const cubeSizeSV = useSharedValue(DEFAULT_CUBE_SIZE);

  const effectiveAmplitude = useDerivedValue(() =>
    minSV.value + audioAmplitude.value * (maxSV.value - minSV.value)
  );

  const setMinAmplitude = useCallback((v: number) => {
    setMinAmplitudeState(v);
    minSV.value = v;
  }, []);

  const setMaxAmplitude = useCallback((v: number) => {
    setMaxAmplitudeState(v);
    maxSV.value = v;
  }, []);

  const setDitherIntensity = useCallback((v: number) => {
    setDitherIntensityState(v);
    ditherSV.value = v;
  }, []);

  const setColorCount = useCallback((v: 1 | 2 | 3) => {
    setColorCountState(v);
    colorCountSV.value = v;
  }, []);

  const setCubeSize = useCallback((v: number) => {
    setCubeSizeState(v);
    cubeSizeSV.value = v;
  }, []);

  return {
    minAmplitude,
    maxAmplitude,
    ditherIntensity,
    colorCount,
    cubeEnabled,
    cubeSize,
    setMinAmplitude,
    setMaxAmplitude,
    setDitherIntensity,
    setColorCount,
    // setCubeEnabled is from useState with no SharedValue—cube overlay is conditionally mounted, not shader-driven
    setCubeEnabled,
    setCubeSize,
    effectiveAmplitude,
    ditherSV,
    colorCountSV,
    cubeSizeSV,
  };
}

# Glow Dev Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a long-press-triggered developer panel that slides from the top of the recording screen, letting you tune RecordingGlow shader uniforms and a new glass-cube refraction overlay in real-time.

**Architecture:** Five tasks — a state hook, an update to the existing glow shader, a new cube-overlay shader canvas, the dev sheet UI (with a reusable slider built from PanGesture), and wiring everything into the recording screen. No new npm packages needed.

**Tech Stack:** React Native (Expo managed), NativeWind, @shopify/react-native-skia ^2.6.3, react-native-reanimated ~4.1.1, react-native-gesture-handler ^2.31.2

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `mobile/src/hooks/useGlowDevControls.ts` | All dev control state + derived SharedValues |
| Modify | `mobile/src/components/ui/RecordingGlow.tsx` | Add `iDither` + `iColorCount` uniforms, accept optional SharedValue props |
| Create | `mobile/src/components/ui/CubeRefractionOverlay.tsx` | New canvas with glass-cube refraction shader |
| Create | `mobile/src/components/ui/GlowDevSheet.tsx` | Top-sliding dev panel with sliders and toggles |
| Modify | `mobile/src/components/ui/index.ts` | Export new components |
| Modify | `mobile/app/recording/index.tsx` | Add long-press gesture, mount dev components |

---

## Task 1: `useGlowDevControls` hook

**Files:**
- Create: `mobile/src/hooks/useGlowDevControls.ts`

- [ ] **Step 1: Create the hook file with this exact content**

```typescript
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
```

- [ ] **Step 2: Verify TypeScript compiles**

Run from the `mobile/` directory:
```bash
npx tsc --noEmit 2>&1 | grep "useGlowDevControls"
```
Expected: no output (no errors for this file).

- [ ] **Step 3: Commit**

```bash
git add mobile/src/hooks/useGlowDevControls.ts
git commit -m "feat: useGlowDevControls hook for glow dev tool"
```

---

## Task 2: Update RecordingGlow shader

**Files:**
- Modify: `mobile/src/components/ui/RecordingGlow.tsx`

- [ ] **Step 1: Replace the entire file with the updated version**

```typescript
// mobile/src/components/ui/RecordingGlow.tsx
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
```

- [ ] **Step 2: Verify no TypeScript errors for this file**

```bash
npx tsc --noEmit 2>&1 | grep "RecordingGlow"
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add mobile/src/components/ui/RecordingGlow.tsx
git commit -m "feat: add iDither and iColorCount uniforms to RecordingGlow shader"
```

---

## Task 3: CubeRefractionOverlay

**Files:**
- Create: `mobile/src/components/ui/CubeRefractionOverlay.tsx`
- Modify: `mobile/src/components/ui/index.ts`

- [ ] **Step 1: Create CubeRefractionOverlay.tsx**

```typescript
// mobile/src/components/ui/CubeRefractionOverlay.tsx
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

  float3 color = glowAt(refractedUV * iResolution, iAmplitude, iTime);

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
```

- [ ] **Step 2: Export from index.ts**

In `mobile/src/components/ui/index.ts`, add these two lines after the RecordingGlow export lines:

```typescript
export { CubeRefractionOverlay } from './CubeRefractionOverlay';
export type { CubeRefractionOverlayProps } from './CubeRefractionOverlay';
```

- [ ] **Step 3: Verify TypeScript**

```bash
npx tsc --noEmit 2>&1 | grep "CubeRefraction"
```
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add mobile/src/components/ui/CubeRefractionOverlay.tsx mobile/src/components/ui/index.ts
git commit -m "feat: CubeRefractionOverlay shader canvas"
```

---

## Task 4: GlowDevSheet

**Files:**
- Create: `mobile/src/components/ui/GlowDevSheet.tsx`

- [ ] **Step 1: Create GlowDevSheet.tsx**

```typescript
// mobile/src/components/ui/GlowDevSheet.tsx
import { useEffect } from 'react';
import { View, Text, TouchableOpacity } from 'react-native';
import { GestureDetector, Gesture } from 'react-native-gesture-handler';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  runOnJS,
} from 'react-native-reanimated';
import type { GlowDevControls } from '../../hooks/useGlowDevControls';

const TRACK_WIDTH = 200;

// ─── DevSlider ───────────────────────────────────────────────────────────────

interface DevSliderProps {
  value: number;
  min: number;
  max: number;
  onChange: (v: number) => void;
}

function DevSlider({ value, min, max, onChange }: DevSliderProps) {
  const initialOffset = ((value - min) / (max - min)) * TRACK_WIDTH;
  const offsetX = useSharedValue(initialOffset);
  const startX = useSharedValue(initialOffset);

  const pan = Gesture.Pan()
    .onBegin(() => { startX.value = offsetX.value; })
    .onUpdate((e) => {
      const next = Math.max(0, Math.min(TRACK_WIDTH, startX.value + e.translationX));
      offsetX.value = next;
      const newVal = min + (next / TRACK_WIDTH) * (max - min);
      runOnJS(onChange)(parseFloat(newVal.toFixed(2)));
    });

  const fillStyle = useAnimatedStyle(() => ({ width: offsetX.value }));
  const thumbStyle = useAnimatedStyle(() => ({
    transform: [{ translateX: offsetX.value - 8 }],
  }));

  return (
    <GestureDetector gesture={pan}>
      <View style={{ width: TRACK_WIDTH, height: 32, justifyContent: 'center' }}>
        <View style={{ height: 3, backgroundColor: 'rgba(255,255,255,0.15)', borderRadius: 2, width: TRACK_WIDTH }}>
          <Animated.View style={[{ height: 3, backgroundColor: '#c6eb52', borderRadius: 2 }, fillStyle]} />
        </View>
        <Animated.View style={[{
          position: 'absolute',
          width: 16,
          height: 16,
          borderRadius: 8,
          backgroundColor: '#ffffff',
          top: 8,
          shadowColor: '#000',
          shadowOffset: { width: 0, height: 1 },
          shadowOpacity: 0.3,
          shadowRadius: 2,
        }, thumbStyle]} />
      </View>
    </GestureDetector>
  );
}

// ─── Segment ─────────────────────────────────────────────────────────────────

interface SegmentProps {
  options: (1 | 2 | 3)[];
  value: 1 | 2 | 3;
  onChange: (v: 1 | 2 | 3) => void;
}

function Segment({ options, value, onChange }: SegmentProps) {
  return (
    <View style={{ flexDirection: 'row', gap: 4 }}>
      {options.map((opt) => (
        <TouchableOpacity
          key={opt}
          onPress={() => onChange(opt)}
          style={{
            width: 36,
            height: 28,
            borderRadius: 6,
            backgroundColor: value === opt ? '#c6eb52' : 'rgba(255,255,255,0.1)',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          <Text style={{ color: value === opt ? '#060707' : '#ffffff', fontSize: 13, fontWeight: '600' }}>
            {opt}
          </Text>
        </TouchableOpacity>
      ))}
    </View>
  );
}

// ─── Toggle ──────────────────────────────────────────────────────────────────

interface ToggleProps {
  value: boolean;
  onChange: (v: boolean) => void;
}

function Toggle({ value, onChange }: ToggleProps) {
  return (
    <View style={{ flexDirection: 'row', gap: 4 }}>
      {([false, true] as const).map((opt) => (
        <TouchableOpacity
          key={String(opt)}
          onPress={() => onChange(opt)}
          style={{
            paddingHorizontal: 14,
            height: 28,
            borderRadius: 6,
            backgroundColor: value === opt ? '#c6eb52' : 'rgba(255,255,255,0.1)',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          <Text style={{ color: value === opt ? '#060707' : '#ffffff', fontSize: 12, fontWeight: '600' }}>
            {opt ? 'on' : 'off'}
          </Text>
        </TouchableOpacity>
      ))}
    </View>
  );
}

// ─── Row / Divider ────────────────────────────────────────────────────────────

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingVertical: 8 }}>
      <Text style={{ color: 'rgba(255,255,255,0.55)', fontSize: 12, width: 100 }}>{label}</Text>
      {children}
    </View>
  );
}

function Divider({ label }: { label: string }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', marginVertical: 6 }}>
      <View style={{ flex: 1, height: 1, backgroundColor: 'rgba(255,255,255,0.08)' }} />
      <Text style={{ color: 'rgba(255,255,255,0.25)', fontSize: 10, paddingHorizontal: 8 }}>{label}</Text>
      <View style={{ flex: 1, height: 1, backgroundColor: 'rgba(255,255,255,0.08)' }} />
    </View>
  );
}

// ─── GlowDevSheet ─────────────────────────────────────────────────────────────

export interface GlowDevSheetProps {
  controls: GlowDevControls;
  visible: boolean;
  onDismiss: () => void;
}

export function GlowDevSheet({ controls, visible, onDismiss }: GlowDevSheetProps) {
  const {
    minAmplitude, maxAmplitude, ditherIntensity, colorCount,
    cubeEnabled, cubeSize,
    setMinAmplitude, setMaxAmplitude, setDitherIntensity, setColorCount,
    setCubeEnabled, setCubeSize,
  } = controls;

  const translateY = useSharedValue(-420);

  useEffect(() => {
    translateY.value = withSpring(visible ? 0 : -420, {
      damping: 22,
      stiffness: 220,
    });
  }, [visible]);

  const sheetStyle = useAnimatedStyle(() => ({
    transform: [{ translateY: translateY.value }],
  }));

  return (
    <Animated.View
      style={[{
        position: 'absolute',
        top: 0,
        left: 0,
        right: 0,
        zIndex: 100,
        backgroundColor: 'rgba(8,8,12,0.94)',
        borderBottomLeftRadius: 18,
        borderBottomRightRadius: 18,
        paddingHorizontal: 20,
        paddingTop: 54,
        paddingBottom: 18,
      }, sheetStyle]}
      pointerEvents={visible ? 'auto' : 'none'}
    >
      <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
        <Text style={{ color: '#ffffff', fontSize: 11, fontWeight: '700', letterSpacing: 1.5, textTransform: 'uppercase', opacity: 0.7 }}>
          Glow Dev Controls
        </Text>
        <TouchableOpacity onPress={onDismiss} hitSlop={12}>
          <Text style={{ color: 'rgba(255,255,255,0.45)', fontSize: 18, lineHeight: 20 }}>✕</Text>
        </TouchableOpacity>
      </View>

      <Row label="Min amplitude">
        <DevSlider value={minAmplitude} min={0} max={1} onChange={setMinAmplitude} />
      </Row>
      <Row label="Max amplitude">
        <DevSlider value={maxAmplitude} min={0} max={1} onChange={setMaxAmplitude} />
      </Row>
      <Row label="Dither">
        <DevSlider value={ditherIntensity} min={0} max={1} onChange={setDitherIntensity} />
      </Row>
      <Row label="Colors">
        <Segment options={[1, 2, 3]} value={colorCount} onChange={setColorCount} />
      </Row>

      <Divider label="Cube Layer" />

      <Row label="Cube overlay">
        <Toggle value={cubeEnabled} onChange={setCubeEnabled} />
      </Row>
      <Row label="Cube size">
        <DevSlider value={cubeSize} min={4} max={64} onChange={(v) => setCubeSize(Math.round(v))} />
      </Row>
    </Animated.View>
  );
}
```

- [ ] **Step 2: Add export to index.ts**

In `mobile/src/components/ui/index.ts`, add after the CubeRefractionOverlay export lines:

```typescript
export { GlowDevSheet } from './GlowDevSheet';
export type { GlowDevSheetProps } from './GlowDevSheet';
```

- [ ] **Step 3: Verify TypeScript**

```bash
npx tsc --noEmit 2>&1 | grep "GlowDevSheet"
```
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add mobile/src/components/ui/GlowDevSheet.tsx mobile/src/components/ui/index.ts
git commit -m "feat: GlowDevSheet top-sliding dev panel"
```

---

## Task 5: Wire up recording screen

**Files:**
- Modify: `mobile/app/recording/index.tsx`

- [ ] **Step 1: Replace recording/index.tsx with the wired-up version**

```typescript
// mobile/app/recording/index.tsx
import { useState, useRef } from 'react';
import { View, Text, TouchableOpacity, Animated, ActivityIndicator } from 'react-native';
import { GestureDetector, Gesture, GestureHandlerRootView } from 'react-native-gesture-handler';
import { router } from 'expo-router';
import { useVoiceRecorder } from '../../src/hooks/useVoiceRecorder';
import { transcribeAudio } from '../../src/services/transcription';
import api from '../../src/services/api';
import { colors } from '../../src/constants/theme';
import { RecordingGlow } from '../../src/components/ui/RecordingGlow';
import { CubeRefractionOverlay } from '../../src/components/ui/CubeRefractionOverlay';
import { GlowDevSheet } from '../../src/components/ui/GlowDevSheet';
import { useGlowDevControls } from '../../src/hooks/useGlowDevControls';

export default function RecordingModal() {
  const { start, stop, isRecording, duration, amplitude } = useVoiceRecorder();
  const [phase, setPhase] = useState<'idle' | 'recording' | 'processing' | 'error'>('idle');
  const [error, setError] = useState<string | null>(null);
  const [devSheetVisible, setDevSheetVisible] = useState(false);
  const pulseAnim = useRef(new Animated.Value(1)).current;
  const pulseLoop = useRef<Animated.CompositeAnimation | null>(null);

  const devControls = useGlowDevControls(amplitude);

  // runOnJS cannot pass a function as argument — wrap the toggle in a plain JS function
  const toggleDevSheet = () => setDevSheetVisible((prev) => !prev);

  const longPress = Gesture.LongPress()
    .minDuration(600)
    .onEnd(() => {
      'worklet';
      runOnJS(toggleDevSheet)();
    });

  const startPulse = () => {
    pulseLoop.current = Animated.loop(
      Animated.sequence([
        Animated.timing(pulseAnim, { toValue: 1.2, duration: 700, useNativeDriver: true }),
        Animated.timing(pulseAnim, { toValue: 1, duration: 700, useNativeDriver: true }),
      ])
    );
    pulseLoop.current.start();
  };

  const stopPulse = () => {
    pulseLoop.current?.stop();
    Animated.timing(pulseAnim, { toValue: 1, duration: 150, useNativeDriver: true }).start();
  };

  const handleStartRecording = async () => {
    try {
      setError(null);
      setPhase('recording');
      await start();
      startPulse();
    } catch (e: any) {
      setError(e.message);
      setPhase('error');
    }
  };

  const handleDone = async () => {
    if (!isRecording) return;
    stopPulse();
    setPhase('processing');

    try {
      const result = await stop();
      const transcript = await transcribeAudio(result.uri, result.durationSeconds);

      const entryRes = await api.post('/entries', {
        rawTranscript: transcript,
        editedTranscript: transcript,
        audioDurationSeconds: result.durationSeconds,
        recordedAt: new Date().toISOString(),
        inputType: 'voice',
      });
      const entryId: string = entryRes.data.data.id;

      const analyzeRes = await api.post(`/analyze/${entryId}`);
      const sessionId: string = analyzeRes.data.data.sessionId;

      router.replace(`/thread/${sessionId}`);
    } catch (e: any) {
      const serverMsg = (e as any)?.response?.data?.error?.message;
      setError(serverMsg ?? e.message ?? 'Something went wrong. Try again.');
      setPhase('error');
    }
  };

  const handleClose = () => {
    router.back();
  };

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <GestureDetector gesture={longPress}>
        <View className="flex-1" style={{ backgroundColor: 'rgba(6,6,11,0.95)' }}>
          <RecordingGlow
            amplitude={devControls.effectiveAmplitude}
            ditherIntensity={devControls.ditherSV}
            colorCount={devControls.colorCountSV}
            visible={isRecording}
          />

          {devControls.cubeEnabled && (
            <CubeRefractionOverlay
              amplitude={devControls.effectiveAmplitude}
              cubeSize={devControls.cubeSizeSV}
            />
          )}

          <GlowDevSheet
            controls={devControls}
            visible={devSheetVisible}
            onDismiss={() => setDevSheetVisible(false)}
          />

          {/* Dismiss area at top */}
          <TouchableOpacity className="flex-1" onPress={handleClose} />

          {/* Bottom sheet */}
          <View className="bg-background rounded-t-3xl px-6 pt-4 pb-12">
            <View className="w-8 h-1 bg-border rounded-full self-center mb-6" />

            {phase === 'error' ? (
              <View className="items-center py-8">
                <Text className="text-danger text-base mb-4">{error}</Text>
                <TouchableOpacity onPress={() => setPhase('idle')} className="bg-muted rounded-full px-6 py-3">
                  <Text className="text-foreground text-sm font-semibold">Try again</Text>
                </TouchableOpacity>
              </View>
            ) : phase === 'processing' ? (
              <View className="items-center py-8">
                <ActivityIndicator color={colors.accent} size="large" style={{ marginBottom: 16 }} />
                <Text className="text-muted-foreground text-sm">Taisa is reading your entry…</Text>
              </View>
            ) : (
              <View className="items-center">
                <Text className="text-text-tertiary text-xs font-bold tracking-widest uppercase mb-6">
                  {isRecording ? 'Recording' : 'Ready'}
                </Text>

                {isRecording && (
                  <Text className="text-lime-700 text-lg tracking-widest mb-4">〜 〜 〜 〜 〜</Text>
                )}

                <Animated.View style={{ transform: [{ scale: pulseAnim }] }}>
                  <TouchableOpacity
                    onPress={isRecording ? undefined : handleStartRecording}
                    className="w-16 h-16 rounded-full bg-primary items-center justify-center mb-4"
                    style={{ shadowColor: '#cdec1a', shadowOffset: { width: 0, height: 4 }, shadowOpacity: 0.5, shadowRadius: 12 }}
                  >
                    <Text className="text-2xl">🎤</Text>
                  </TouchableOpacity>
                </Animated.View>

                {isRecording ? (
                  <>
                    <Text className="text-foreground text-xl font-bold mb-1">{formatDuration(duration)}</Text>
                    <TouchableOpacity onPress={handleDone} className="bg-muted rounded-full px-8 py-3 mt-4">
                      <Text className="text-foreground text-sm font-semibold">Done</Text>
                    </TouchableOpacity>
                  </>
                ) : (
                  <Text className="text-text-tertiary text-sm">Tap to start recording</Text>
                )}
              </View>
            )}
          </View>
        </View>
      </GestureDetector>
    </GestureHandlerRootView>
  );
}

function formatDuration(seconds: number): string {
  const m = Math.floor(seconds / 60).toString().padStart(2, '0');
  const s = (seconds % 60).toString().padStart(2, '0');
  return `${m}:${s}`;
}
```

**Important note on the worklet:** The `longPress.onEnd` callback runs on the UI thread. `runOnJS` must be imported from `react-native-reanimated`. Add this import to the file:

```typescript
import { runOnJS } from 'react-native-reanimated';
```

Then ensure the gesture is defined with a `toggleDevSheet` wrapper (already shown in Step 1 above). The key pattern is:

```typescript
const toggleDevSheet = () => setDevSheetVisible((prev) => !prev);

const longPress = Gesture.LongPress()
  .minDuration(600)
  .onEnd(() => {
    'worklet';
    runOnJS(toggleDevSheet)();
  });
```

- [ ] **Step 2: Add `runOnJS` import and fix the gesture callback**

The final import block for `recording/index.tsx` should be:

```typescript
import { useState, useRef } from 'react';
import { View, Text, TouchableOpacity, Animated, ActivityIndicator } from 'react-native';
import { GestureDetector, Gesture, GestureHandlerRootView } from 'react-native-gesture-handler';
import { runOnJS } from 'react-native-reanimated';
import { router } from 'expo-router';
import { useVoiceRecorder } from '../../src/hooks/useVoiceRecorder';
import { transcribeAudio } from '../../src/services/transcription';
import api from '../../src/services/api';
import { colors } from '../../src/constants/theme';
import { RecordingGlow } from '../../src/components/ui/RecordingGlow';
import { CubeRefractionOverlay } from '../../src/components/ui/CubeRefractionOverlay';
import { GlowDevSheet } from '../../src/components/ui/GlowDevSheet';
import { useGlowDevControls } from '../../src/hooks/useGlowDevControls';
```

- [ ] **Step 3: Verify TypeScript compiles cleanly**

```bash
npx tsc --noEmit 2>&1 | grep -E "recording/index|GlowDev|CubeRef"
```
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add mobile/app/recording/index.tsx
git commit -m "feat: wire glow dev tool into recording screen — long-press to open"
```

---

## Verification

- [ ] **Start the app and open the recording modal**

```bash
# from repo root
npm run mobile
```

- [ ] **Long-press anywhere on the dark background of the recording modal**

Expected: The dev sheet slides down from the top with spring animation.

- [ ] **Drag the Min/Max amplitude sliders**

Expected: The glow intensity at the bottom of the screen responds immediately (the glow must be visible — tap the record button first to trigger `isRecording = true`).

- [ ] **Change Colors from 2 → 3**

Expected: A violet blob appears in the center of the glow alongside lime and peach.

- [ ] **Increase Dither to ~0.5**

Expected: Visible grain/noise texture overlaid on the glow colors.

- [ ] **Toggle Cube overlay ON**

Expected: The glass-cube refraction grid appears over the glow area.

- [ ] **Drag Cube size slider left (small) and right (large)**

Expected: Grid cell size visibly changes — small values produce a fine grid, large values produce a few big cubes.

- [ ] **Long-press again or tap ✕**

Expected: Dev sheet springs back off-screen.

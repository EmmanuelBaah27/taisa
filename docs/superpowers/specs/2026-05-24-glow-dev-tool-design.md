# Glow Dev Tool — Design Spec

**Date:** 2026-05-24
**Status:** Approved

---

## Overview

A developer-only control panel for tuning `RecordingGlow` in real-time. Triggered by long-pressing the glow area, a sheet slides down from the top of the screen (leaving the glow fully visible at the bottom). Controls drive live shader uniforms so changes are seen immediately. Values are not persisted — the tool is for finding the right feel, not storing it.

---

## Architecture

### Components

| Component | Purpose |
|---|---|
| `RecordingGlow` (existing) | Unchanged — aurora blob shader at bottom |
| `CubeRefractionOverlay` | New Canvas, same position/size as glow, cube/refraction shader on top |
| `GlowDevSheet` | Reanimated-animated View sliding from top, houses all controls |
| `useGlowDevControls` | Hook owning all tunable state + deriving SharedValues for shaders |

### State flow

```
useGlowDevControls
  ├── useState: minAmplitude, maxAmplitude, ditherIntensity, colorCount, cubeEnabled, cubeSize
  └── derives SharedValues → passed as uniforms to RecordingGlow + CubeRefractionOverlay
```

Regular `useState` drives the sliders (slow path). The hook derives `SharedValue` equivalents for the animation/shader path. No cross-contamination of the two.

### Trigger

Wrap the parent container in `LongPressGestureHandler` (react-native-gesture-handler, already in Expo). Long-press toggles `GlowDevSheet` visibility. Long-press again or tapping ✕ dismisses it.

`GlowDevSheet` is always mounted, translated off-screen above (`translateY: -sheetHeight`). Long-press springs it into view. Uses Reanimated `withSpring` — no extra library.

---

## Shader Design

### RecordingGlow — new uniforms

Two new uniforms added to the existing SkSL shader:

- `iDither` — float, 0.0–1.0. A hash-based pseudo-random noise function layered onto final color output. No texture needed — pure math.
- `iColorCount` — float, 1–3. Controls how many color stops participate in the blend:
  - 1 → lime only
  - 2 → lime + peach (current behaviour)
  - 3 → lime + peach + a third stop (violet, derived by mixing the two)

The existing `iAmplitude` uniform remains. The dev controls set the range: the incoming audio amplitude (0–1 from parent) is linearly mapped so that silence → `minAmplitude` and peak → `maxAmplitude`. Formula: `effectiveAmplitude = minAmplitude + audioAmplitude * (maxAmplitude - minAmplitude)`. This mapping happens in `useGlowDevControls` via a derived SharedValue.

### CubeRefractionOverlay — new shader

New `Canvas` + new SkSL shader. Same `position: absolute, bottom: 0` as the glow.

The shader:
1. Divides `fragCoord` into a grid of square cells using `iCubeSize` uniform
2. Computes a local UV offset per cell — simulates a glass lens bent normal based on cell-relative position
3. Re-derives the glow color analytically at the refracted UV (no inter-shader texture reads — the glow color math is inlined)
4. Adds a subtle edge highlight at cell borders for the glass facet feel
5. Blends over the glow using premultiplied alpha

New uniforms: `iResolution`, `iCubeSize`, `iTime` (reuses same clock), `iAmplitude`.

`CubeRefractionOverlay` only renders when `cubeEnabled` is true.

---

## Dev Sheet UI

Sheet appears from the top edge. Semi-transparent dark background so the glow remains readable below.

```
┌─────────────────────────────────────┐
│  Glow Dev Controls              ✕   │
├─────────────────────────────────────┤
│  Min amplitude      ●━━━━━━━━━━━━━  │
│  Max amplitude      ━━━━━━━━━━━●━━  │
│  Dither             ━━━━●━━━━━━━━━  │
│  Colors             [ 1 | 2 | 3 ]   │
├──────── Cube Layer ─────────────────┤
│  Cube overlay       ○ off  ● on     │
│  Cube size          ━━━━━━━●━━━━━━  │
└─────────────────────────────────────┘
```

**Controls:**
- Sliders: React Native built-in `Slider` — min/max amplitude (0.0–1.0), dither (0.0–1.0), cube size (4–64px grid cell)
- Color count: segmented row of three `TouchableOpacity` buttons (1 / 2 / 3)
- Cube toggle: two-option toggle (off / on)

**Styling:** NativeWind throughout. No third-party control library.

**Dismiss:** ✕ button or long-press again anywhere on the glow.

---

## Controls Reference

| Control | Range | Shader target |
|---|---|---|
| Min amplitude | 0.0–1.0 | Lower bound of `iAmplitude` at silence |
| Max amplitude | 0.0–1.0 | Upper bound of `iAmplitude` at peak noise |
| Dither intensity | 0.0–1.0 | `iDither` in RecordingGlow shader |
| Color count | 1, 2, 3 | `iColorCount` in RecordingGlow shader |
| Cube overlay | off / on | Mounts/unmounts CubeRefractionOverlay |
| Cube size | 4–64 | `iCubeSize` in CubeRefractionOverlay shader |

---

## Out of Scope

- Persisting values across sessions
- Exporting tuned values to code automatically
- Any user-facing UI (this is dev-only)
- Cube refraction reading glow as a texture (analytical re-derivation used instead)

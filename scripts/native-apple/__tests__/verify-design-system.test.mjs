import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import { rawVisualValues } from '../verify-design-system.mjs';

test('feature views contain no raw color literals', async () => {
  assert.deepEqual(await rawVisualValues('apple/TaisaApp'), []);
});

test('recording glow uses one linked stitchable shader with anchored procedural grain', async () => {
  const metal = await readFile(
    'apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/RecordingGlow.metal',
    'utf8',
  );
  const swift = await readFile(
    'apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/RecordingReactiveGlow.swift',
    'utf8',
  );

  assert.match(metal, /\[\[\s*stitchable\s*\]\]\s*half4\s+recordingGlow\s*\(/);
  assert.match(swift, /ShaderLibrary\.bundle\(\.module\)\.recordingGlow\s*\(/);
  assert.doesNotMatch(swift, /TimelineView|figma\.com|https?:\/\//);
  assert.doesNotMatch(metal, /\btime\b|texture2d/);
});

test('recording glow composites its color field over white instead of producing dark alpha lobes', async () => {
  const metal = await readFile(
    'apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/RecordingGlow.metal',
    'utf8',
  );

  assert.match(metal, /mix\(float3\(1\.0\),\s*glowColor,\s*alpha\)/);
  assert.match(metal, /rgb\s*\/\s*max\(weightSum,\s*0\.0001\)/);
  assert.match(metal, /return half4\(half3\(compositedColor\),\s*half\(1\.0\)\)/);
  assert.doesNotMatch(metal, /rgb\s*=\s*clamp\(rgb,\s*0\.0,\s*1\.0\)\s*\*\s*alpha/);
});

test('recording glow softly unions adjacent lobes so white seams cannot split the palette', async () => {
  const metal = await readFile(
    'apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/RecordingGlow.metal',
    'utf8',
  );

  assert.match(metal, /static float softUnion\s*\(float totalWeight\)/);
  assert.match(metal, /softUnion\(weightSum\)/);
  assert.doesNotMatch(metal, /float weightedField\s*=\s*max\s*\(/);
});

test('recording glow exposes fine adjustable film grain rather than coarse pixel cells', async () => {
  const metal = await readFile(
    'apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/RecordingGlow.metal',
    'utf8',
  );
  const tuner = await readFile(
    'apple/TaisaPreview/RecordingGlowTuningView.swift',
    'utf8',
  );

  assert.match(metal, /static float filmNoise\s*\(/);
  assert.match(metal, /mix\(1\.25,\s*0\.45,\s*size\)/);
  assert.match(metal, /frequency \* 1\.73/);
  assert.doesNotMatch(metal, /mix\(0\.08,\s*0\.34,\s*grain\.y\)/);
  assert.match(tuner, /slider\("Grain intensity",\s*value:\s*\$preset\.grain\.amount\)/);
  assert.match(tuner, /slider\("Grain size",\s*value:\s*\$preset\.grain\.scale\)/);
});

test('recording glow tuning offers an ephemeral live microphone input', async () => {
  const tuner = await readFile(
    'apple/TaisaPreview/RecordingGlowTuningView.swift',
    'utf8',
  );

  assert.match(tuner, /AVAudioEngine/);
  assert.match(tuner, /Live microphone/);
  assert.match(tuner, /installTap/);
  assert.doesNotMatch(tuner, /write\(|FileHandle|Data\.write|AVAudioRecorder/);
});

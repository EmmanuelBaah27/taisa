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

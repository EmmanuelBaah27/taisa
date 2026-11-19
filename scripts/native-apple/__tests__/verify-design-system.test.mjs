import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  nativeControlRoots,
  rawInteractiveControlViolations,
  rawVisualValues,
} from '../verify-design-system.mjs';

async function withControlFixture(files, policy, assertion) {
  const repositoryRoot = await mkdtemp(path.join(os.tmpdir(), 'taisa-ds-controls-'));
  try {
    for (const [relativePath, source] of Object.entries(files)) {
      const target = path.join(repositoryRoot, relativePath);
      await mkdir(path.dirname(target), { recursive: true });
      await writeFile(target, source);
    }
    const policyPath = path.join(repositoryRoot, 'policy.json');
    await writeFile(policyPath, JSON.stringify(policy));
    await assertion({ repositoryRoot, policyPath });
  } finally {
    await rm(repositoryRoot, { recursive: true, force: true });
  }
}

const emptyControlPolicy = {
  controlledConstructors: ['Button'],
  primitiveFiles: [],
  legacyOccurrences: [],
};

test('rejects raw controls in Product source', async () => {
  await withControlFixture(
    { 'apple/TaisaApp/FeatureView.swift': 'struct FeatureView { var body: some View { Button("Save") {} } }\n' },
    emptyControlPolicy,
    async ({ repositoryRoot, policyPath }) => {
      const violations = await rawInteractiveControlViolations({
        roots: ['apple/TaisaApp'], policyPath, repositoryRoot,
      });
      assert.deepEqual(violations.map(({ kind, file }) => ({ kind, file })), [
        { kind: 'unclassified-control', file: 'apple/TaisaApp/FeatureView.swift' },
      ]);
    },
  );
});

test('rejects raw controls in composite design-system source', async () => {
  await withControlFixture(
    { 'apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/TaskComposer.swift': 'Button("Due") {}\n' },
    emptyControlPolicy,
    async ({ repositoryRoot, policyPath }) => {
      const violations = await rawInteractiveControlViolations({
        roots: ['apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem'], policyPath, repositoryRoot,
      });
      assert.equal(violations[0]?.kind, 'unclassified-control');
    },
  );
});

test('allows a designated primitive wrapper to use the platform control', async () => {
  const file = 'apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/TaisaButton.swift';
  await withControlFixture(
    { [file]: 'public struct TaisaButton { var body: some View { Button("Continue") {} } }\n' },
    { ...emptyControlPolicy, primitiveFiles: [file] },
    async ({ repositoryRoot, policyPath }) => {
      assert.deepEqual(await rawInteractiveControlViolations({
        roots: ['apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem'], policyPath, repositoryRoot,
      }), []);
    },
  );
});

test('allows only the exact approved legacy occurrence', async () => {
  const file = 'apple/TaisaApp/LegacyView.swift';
  const policy = {
    ...emptyControlPolicy,
    legacyOccurrences: [{
      file, constructor: 'Button', line: 1, column: 1,
      sourceHash: '8f6006c4b2687a7f4c46969083013066ac923f5d2cb28863990ac06fbcf4063a',
      owner: 'APF-75', reason: 'Existing migration debt',
    }],
  };
  await withControlFixture(
    { [file]: 'Button("Legacy") {}\n' },
    policy,
    async ({ repositoryRoot, policyPath }) => {
      assert.deepEqual(await rawInteractiveControlViolations({
        roots: ['apple/TaisaApp'], policyPath, repositoryRoot,
      }), []);
    },
  );
});

test('rejects a changed legacy occurrence and reports the stale approval', async () => {
  const file = 'apple/TaisaApp/LegacyView.swift';
  const policy = {
    ...emptyControlPolicy,
    legacyOccurrences: [{
      file, constructor: 'Button', line: 1, column: 1,
      sourceHash: '8f6006c4b2687a7f4c46969083013066ac923f5d2cb28863990ac06fbcf4063a',
      owner: 'APF-75', reason: 'Existing migration debt',
    }],
  };
  await withControlFixture(
    { [file]: 'Button("Changed") {}\n' },
    policy,
    async ({ repositoryRoot, policyPath }) => {
      const violations = await rawInteractiveControlViolations({
        roots: ['apple/TaisaApp'], policyPath, repositoryRoot,
      });
      assert.deepEqual(violations.map(({ kind }) => kind).sort(), [
        'stale-legacy-occurrence', 'unclassified-control',
      ]);
    },
  );
});

test('rejects a stale legacy occurrence after migration removes the raw control', async () => {
  const file = 'apple/TaisaApp/LegacyView.swift';
  await withControlFixture(
    { [file]: 'TaisaButton(role: .primary, label: "Legacy") {}\n' },
    {
      ...emptyControlPolicy,
      legacyOccurrences: [{
        file, constructor: 'Button', line: 1, column: 1,
        sourceHash: '8f6006c4b2687a7f4c46969083013066ac923f5d2cb28863990ac06fbcf4063a',
        owner: 'APF-75', reason: 'Existing migration debt',
      }],
    },
    async ({ repositoryRoot, policyPath }) => {
      const violations = await rawInteractiveControlViolations({
        roots: ['apple/TaisaApp'], policyPath, repositoryRoot,
      });
      assert.deepEqual(violations.map(({ kind }) => kind), ['stale-legacy-occurrence']);
    },
  );
});

test('ignores constructor text in comments and string literals', async () => {
  await withControlFixture(
    { 'apple/TaisaApp/Documentation.swift': '// Button("Comment") {}\nlet example = "Button(\\"String\\")"\n' },
    emptyControlPolicy,
    async ({ repositoryRoot, policyPath }) => {
      assert.deepEqual(await rawInteractiveControlViolations({
        roots: ['apple/TaisaApp'], policyPath, repositoryRoot,
      }), []);
    },
  );
});

test('detects trailing-closure, qualified, generic, init, and backticked button constructors', async () => {
  const source = [
    'Button { save() } label: { Text("Save") }',
    'SwiftUI.Button("Save") {}',
    'Button<Text>("Save") {}',
    'Button.init("Save") {}',
    '`Button`("Save") {}',
  ].join('\n');
  await withControlFixture(
    { 'apple/TaisaApp/FeatureView.swift': `${source}\n` },
    emptyControlPolicy,
    async ({ repositoryRoot, policyPath }) => {
      const violations = await rawInteractiveControlViolations({
        roots: ['apple/TaisaApp'], policyPath, repositoryRoot,
      });
      assert.equal(violations.filter(({ kind }) => kind === 'unclassified-control').length, 5);
    },
  );
});

test('detects nested and multiline generic button constructors', async () => {
  const source = [
    'Button<Label<Text, Image>>(action: {}) { Label("Save", systemImage: "checkmark") }',
    'Button<',
    '  Label<Text, Image>',
    '>(action: {}) { Label("Delete", systemImage: "trash") }',
  ].join('\n');
  await withControlFixture(
    { 'apple/TaisaApp/FeatureView.swift': `${source}\n` },
    emptyControlPolicy,
    async ({ repositoryRoot, policyPath }) => {
      const violations = await rawInteractiveControlViolations({
        roots: ['apple/TaisaApp'], policyPath, repositoryRoot,
      });
      assert.equal(violations.filter(({ kind }) => kind === 'unclassified-control').length, 2);
    },
  );
});

test('detects controls after escaped delimiters in multiline Swift strings', async () => {
  const source = [
    'let example = """',
    'escaped delimiter: \\"""',
    '"""',
    'Button("Save") {}',
  ].join('\n');
  await withControlFixture(
    { 'apple/TaisaApp/FeatureView.swift': `${source}\n` },
    emptyControlPolicy,
    async ({ repositoryRoot, policyPath }) => {
      const violations = await rawInteractiveControlViolations({
        roots: ['apple/TaisaApp'], policyPath, repositoryRoot,
      });
      assert.deepEqual(
        violations.map(({ kind, line }) => ({ kind, line })),
        [{ kind: 'unclassified-control', line: 4 }],
      );
    },
  );
});

test('changing a multiline legacy invocation invalidates its whole-source fingerprint', async () => {
  const file = 'apple/TaisaApp/LegacyView.swift';
  const original = 'Button(\n    action: { save() },\n    label: { Text("Save") }\n)\n';
  const changed = original.replace('save()', 'delete()');
  await withControlFixture(
    { [file]: changed },
    {
      ...emptyControlPolicy,
      legacyOccurrences: [{
        file, constructor: 'Button', line: 1, column: 1,
        sourceHash: '0000000000000000000000000000000000000000000000000000000000000000',
        owner: 'APF-75', reason: 'Existing migration debt',
      }],
    },
    async ({ repositoryRoot, policyPath }) => {
      const violations = await rawInteractiveControlViolations({
        roots: ['apple/TaisaApp'], policyPath, repositoryRoot,
      });
      assert.deepEqual(violations.map(({ kind }) => kind).sort(), [
        'stale-legacy-occurrence', 'unclassified-control',
      ]);
    },
  );
});

test('Swift masking handles nested comments, raw strings, and Unicode without shifting source positions', async () => {
  const source = [
    '/* outer /* Button("Nested") {} */ still outer */',
    'let example = #"Button("Raw")"#',
    '// emoji 😀 must preserve UTF-16 offsets',
    'Button("Real") {}',
  ].join('\n');
  await withControlFixture(
    { 'apple/TaisaApp/FeatureView.swift': `${source}\n` },
    emptyControlPolicy,
    async ({ repositoryRoot, policyPath }) => {
      const violations = await rawInteractiveControlViolations({
        roots: ['apple/TaisaApp'], policyPath, repositoryRoot,
      });
      assert.deepEqual(
        violations.map(({ kind, line, column }) => ({ kind, line, column })),
        [{ kind: 'unclassified-control', line: 4, column: 1 }],
      );
    },
  );
});

test('rejects primitive paths that escape the canonical DS source root', async () => {
  const escaped = 'apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/../../../../TaisaApp/Fake.swift';
  await withControlFixture(
    {
      'apple/TaisaApp/Fake.swift': 'public struct Fake { var body: some View { Button("Raw") {} } }\n',
      'apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/TaisaButton.swift': 'public struct TaisaButton {}\n',
    },
    { ...emptyControlPolicy, primitiveFiles: [escaped] },
    async ({ repositoryRoot, policyPath }) => {
      await assert.rejects(
        rawInteractiveControlViolations({ roots: ['apple/TaisaApp'], policyPath, repositoryRoot }),
        /canonical design-system source root/,
      );
    },
  );
});

test('rejects malformed and duplicate legacy policy entries', async () => {
  const file = 'apple/TaisaApp/LegacyView.swift';
  const entry = {
    file, constructor: 'Button', line: 1, column: 1,
    sourceHash: '8f6006c4b2687a7f4c46969083013066ac923f5d2cb28863990ac06fbcf4063a',
    owner: '', reason: '',
  };
  await withControlFixture(
    { [file]: 'Button("Legacy") {}\n' },
    { ...emptyControlPolicy, legacyOccurrences: [entry, entry] },
    async ({ repositoryRoot, policyPath }) => {
      await assert.rejects(
        rawInteractiveControlViolations({ roots: ['apple/TaisaApp'], policyPath, repositoryRoot }),
        /valid fields, owner, and semantic reason|duplicate/,
      );
    },
  );
});

test('default roots include shipping feature package sources', async () => {
  assert.ok(nativeControlRoots.includes('apple/Packages/TaisaFoundation/Sources'));
});

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

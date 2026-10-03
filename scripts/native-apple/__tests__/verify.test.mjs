import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import test from 'node:test';
import { join, resolve } from 'node:path';

import { inspectNativeProject } from '../verify.mjs';

const repositoryRoot = resolve(import.meta.dirname, '../../..');

test('declares distinct production, development, and preview identities', async () => {
  const result = await inspectNativeProject(repositoryRoot);

  assert.deepEqual(result.bundleIdentifiers, {
    production: 'com.taisa.app',
    development: 'com.taisa.app.dev',
    preview: 'com.taisa.app.preview',
  });
});

test('production target excludes preview sources and support product', async () => {
  const result = await inspectNativeProject(repositoryRoot);

  assert.deepEqual(result.productionPreviewLeaks, []);
  assert.equal(result.previewArchiveEnabled, false);
});

test('project declares native unit and UI test targets', async () => {
  const result = await inspectNativeProject(repositoryRoot);

  assert.deepEqual(result.testTargets, ['TaisaUnitTests', 'TaisaUITests']);
});

test('preview support is linked only by the preview target', async () => {
  const result = await inspectNativeProject(repositoryRoot);

  assert.deepEqual(result.productionProducts, [
    'TaisaCore',
    'TaisaContracts',
    'TaisaDesignSystem',
  ]);
  assert.deepEqual(result.previewProducts, [
    'TaisaCore',
    'TaisaContracts',
    'TaisaDesignSystem',
    'TaisaPreviewSupport',
  ]);
});

test('metadata generator preserves clean, dirty, and detached repository state', async () => {
  const fixture = await mkdtemp(join(tmpdir(), 'taisa-build-metadata-'));
  const output = join(fixture, 'BuildMetadata.generated.swift');
  execFileSync('git', ['init', '-b', 'fixture'], { cwd: fixture });
  await writeFile(join(fixture, 'README.md'), 'fixture\n');
  execFileSync('git', ['add', 'README.md'], { cwd: fixture });
  execFileSync('git', [
    '-c', 'user.name=Taisa Test',
    '-c', 'user.email=taisa-test@example.invalid',
    'commit', '-m', 'fixture',
  ], { cwd: fixture });

  const script = resolve(repositoryRoot, 'apple/scripts/generate-build-metadata.sh');
  execFileSync(script, [output], {
    env: { ...process.env, TAISA_REPOSITORY_ROOT: fixture },
  });
  assert.match(await readFile(output, 'utf8'), /gitBranch: String\? = "fixture"[\s\S]+isDirty = false/);

  await writeFile(join(fixture, 'dirty.txt'), 'dirty\n');
  execFileSync('git', ['checkout', '--detach'], { cwd: fixture });
  execFileSync(script, [output], {
    env: { ...process.env, TAISA_REPOSITORY_ROOT: fixture },
  });
  assert.match(await readFile(output, 'utf8'), /gitBranch: String\? = nil[\s\S]+isDirty = true/);
});

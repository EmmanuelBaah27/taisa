import assert from 'node:assert/strict';
import test from 'node:test';
import { resolve } from 'node:path';

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

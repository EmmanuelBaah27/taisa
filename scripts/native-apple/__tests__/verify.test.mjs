import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import test from 'node:test';
import { join, resolve } from 'node:path';

import {
  inspectNativeProject,
  inspectProductionBundle,
  unresolvedBuildIdentityPlaceholders,
} from '../verify.mjs';

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

test('production bundle inspection rejects preview code and fixture identifiers', async () => {
  const fixture = await mkdtemp(join(tmpdir(), 'taisa-production-bundle-'));
  const cleanBundle = join(fixture, 'Taisa.app');
  await mkdir(cleanBundle);
  await writeFile(join(cleanBundle, 'Taisa'), 'production foundation');
  assert.deepEqual(await inspectProductionBundle(cleanBundle), []);

  await writeFile(
    join(cleanBundle, 'leak.txt'),
    'TaisaPreview PreviewSupport foundation.default com.taisa.app.preview',
  );
  assert.deepEqual(await inspectProductionBundle(cleanBundle), [
    'PreviewSupport',
    'TaisaPreview',
    'com.taisa.app.preview',
    'foundation.default',
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

test('combined native verification and CI pin every required gate', async () => {
  const packageJSON = JSON.parse(await readFile(resolve(repositoryRoot, 'package.json'), 'utf8'));
  const generatedCheck = await readFile(
    resolve(repositoryRoot, 'scripts/native-apple/verify-generated-project.sh'),
    'utf8',
  );
  const workflow = await readFile(
    resolve(repositoryRoot, '.github/workflows/native-apple.yml'),
    'utf8',
  );
  const combined = packageJSON.scripts['verify:native-apple:all'];

  for (const required of [
    'verify-generated-project.sh',
    'verify:native-contracts',
    'swift test',
    'verify:native-design-system',
    'Taisa-Dev',
    'Taisa-Preview',
    'Release',
    'verify:workflow',
  ]) assert.match(combined, new RegExp(required));

  assert.match(generatedCheck, /mktemp -d/);
  assert.match(generatedCheck, /diff -ru/);
  assert.doesNotMatch(generatedCheck, /git (checkout|reset)/);

  for (const required of [
    'macos-26',
    '/Applications/Xcode_26.1.1.app',
    '17B100',
    '-downloadPlatform iOS',
    '2.46.0',
    'verify:native-apple:all',
    'upload-artifact',
  ]) assert.match(workflow, new RegExp(required.replaceAll('.', '\\.')));
});

test('rejects unexpanded build identity placeholders', () => {
  assert.deepEqual(
    unresolvedBuildIdentityPlaceholders(
      'gitCommit = "$(GIT_COMMIT)"\nbuild = "BUILD_NUMBER"',
    ),
    ['$(GIT_COMMIT)', 'BUILD_NUMBER', 'GIT_COMMIT'],
  );
  assert.deepEqual(
    unresolvedBuildIdentityPlaceholders('gitCommit = "abc123"'),
    [],
  );
});

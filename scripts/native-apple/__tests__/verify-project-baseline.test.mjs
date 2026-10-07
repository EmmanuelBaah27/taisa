import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

test('native Product baseline is iOS 26 and functionality-first', async () => {
  const [baseConfig, project, packageManifest, scope] = await Promise.all([
    readFile('apple/Config/Base.xcconfig', 'utf8'),
    readFile('apple/project.yml', 'utf8'),
    readFile('apple/Packages/TaisaFoundation/Package.swift', 'utf8'),
    readFile('docs/features/swiftui-native-rebuild.md', 'utf8'),
  ]);

  assert.match(baseConfig, /IPHONEOS_DEPLOYMENT_TARGET = 26\.0/);
  assert.match(project, /iOS: "26\.0"/);
  assert.match(packageManifest, /\/\/ swift-tools-version: 6\.0/);
  assert.match(packageManifest, /\.iOS\("26\.0"\)/);
  assert.match(scope, /native-first/i);
  assert.match(scope, /functionality-first/i);
  assert.match(scope, /iOS\/iPadOS 26/);
  assert.doesNotMatch(scope, /visual parity review/i);
  assert.doesNotMatch(scope, /baseline freeze.*prerequisite/i);
});

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

test('Home owns one stable sheet route for planning and prior-week review', async () => {
  const home = await readFile('apple/TaisaApp/Home/HomeView.swift', 'utf8');
  const section = await readFile('apple/TaisaApp/Home/ThisWeekSection.swift', 'utf8');

  assert.match(home, /@State private var activeSheet: ThisWeekSheet\?/);
  assert.match(home, /\.sheet\(item: \$activeSheet\)/);
  assert.equal(home.match(/\.sheet\(/g)?.length, 1);
  assert.doesNotMatch(section, /@State|\.sheet\(/);
  assert.match(section, /openPlanning: \(WeeklyWorkItem\) -> Void/);
  assert.match(section, /openPriorWeekReview: \(Int\) -> Void/);
});

test('preview target compiles every shared conversation response source', async () => {
  const project = await readFile('apple/project.yml', 'utf8');
  const previewTarget = project.match(/  TaisaPreview:\n([\s\S]*?)(?=  TaisaPersonal:)/)?.[1];

  assert.ok(previewTarget, 'TaisaPreview target is missing');
  assert.match(previewTarget, /- path: TaisaApp\/Conversation\/AssistantResponseActions\.swift/);
});

test('sync tests declare the conversation module used by integrated response fixtures', async () => {
  const packageManifest = await readFile('apple/Packages/TaisaFoundation/Package.swift', 'utf8');
  const syncTests = packageManifest.match(
    /\.testTarget\(name: "TaisaSyncTests", dependencies: \[([^\]]*)\]\)/,
  )?.[1];

  assert.ok(syncTests, 'TaisaSyncTests target is missing');
  assert.match(syncTests, /"TaisaConversations"/);
});

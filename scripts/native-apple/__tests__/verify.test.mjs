import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { cp, mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import test from 'node:test';
import { join, resolve } from 'node:path';

import {
  inspectNativeProject,
  inspectProductionBundle,
  inspectPersonalBundle,
  unresolvedBuildIdentityPlaceholders,
  verifyNativeProject,
} from '../verify.mjs';

const repositoryRoot = resolve(import.meta.dirname, '../../..');

// Security regression requested by Task 5 review: native selection bypasses
// the explicit local-only/expiring clipboard boundary.
test('recovery secret has no unrestricted native selection or clipboard route', async () => {
  const view = await readFile(join(repositoryRoot, 'apple/TaisaApp/Recovery/RecoveryView.swift'), 'utf8');
  assert.doesNotMatch(view, /textSelection\(\.enabled\)/);
  assert.match(view, /textSelection\(\.disabled\)/);
  assert.doesNotMatch(view, /Select to copy/);
  assert.match(view, /Use Copy Recovery Key/);
  assert.match(view, /\.localOnly: true/);
  assert.match(view, /\.expirationDate: Date\(\)\.addingTimeInterval\(120\)/);
});

test('verified archive export cannot eagerly allocate its entire file', async () => {
  const document = await readFile(join(repositoryRoot, 'apple/TaisaApp/Recovery/TaisaBackupDocument.swift'), 'utf8');
  assert.doesNotMatch(document, /Data\s*\(\s*contentsOf:|regularFileWithContents:|encryptedBytes/);
  assert.match(document, /PortableArchive\.verify/);
});

test('personal built products reject identity drift, background capabilities and live symbols', async () => {
  const fixture = await mkdtemp(join(tmpdir(), 'taisa-personal-bundle-'));
  const plistPath = join(fixture, 'Info.plist');
  const plist = (extra = '', identity = 'com.taisa.app.personal') => `<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>${identity}</string><key>TaisaEnvironment</key><string>personal</string>${extra}</dict></plist>`;
  await writeFile(plistPath, plist());
  assert.deepEqual(await inspectPersonalBundle(fixture), []);
  await writeFile(plistPath, plist('<key>UIBackgroundModes</key><array><string>remote-notification</string></array>'));
  assert.deepEqual(await inspectPersonalBundle(fixture), ['Personal bundle declares background modes']);
  await writeFile(plistPath, plist('', 'com.taisa.app'));
  assert.deepEqual(await inspectPersonalBundle(fixture), ['Personal bundle identity or environment mismatch']);
  await writeFile(plistPath, plist());
  for (const symbol of ['TaisaCloudKit', 'CKContainer', 'CloudKit.framework']) {
    await writeFile(join(fixture, 'TaisaPersonal'), symbol);
    assert.deepEqual(await inspectPersonalBundle(fixture), [`Personal bundle contains live CloudKit reference: ${symbol}`]);
  }
});

test('personal identity has no paid capabilities, live transport, background mode, or archive', async () => {
  const result = await inspectNativeProject(repositoryRoot);
  assert.deepEqual(result.personalIsolation, {
    personal: {
      bundleIdentifier: 'com.taisa.app.personal',
      entitlementKeys: [],
      linksLiveTransport: false,
      configuresBackgroundMode: false,
      archiveEnabled: false,
    },
  });
});

test('personal capability mutations are rejected without changing live entitlements', async () => {
  const fixture = await mkdtemp(join(tmpdir(), 'taisa-personal-project-'));
  await cp(resolve(repositoryRoot, 'apple'), join(fixture, 'apple'), {
    recursive: true,
    filter: (source) => !source.includes('/Packages/') && !source.includes('/Taisa.xcodeproj/'),
  });
  const liveNames = ['TaisaDev', 'Taisa', 'TaisaPreview'];
  const before = await Promise.all(liveNames.map((name) => readFile(join(fixture, `apple/Config/${name}.entitlements`))));
  const rightsPath = join(fixture, 'apple/Config/TaisaPersonal.entitlements');
  const original = await readFile(rightsPath, 'utf8');
  assert.deepEqual(await verifyNativeProject(fixture), []);
  for (const key of ['aps-environment', 'com.apple.developer.icloud-container-identifiers', 'com.apple.developer.associated-domains']) {
    await writeFile(rightsPath, original.replace('<dict/>', `<dict><key>${key}</key><string>forbidden</string></dict>`));
    assert.ok((await verifyNativeProject(fixture)).includes('Personal app isolation mismatch'));
  }
  await writeFile(rightsPath, original);
  const projectPath = join(fixture, 'apple/project.yml');
  const project = await readFile(projectPath, 'utf8');
  await writeFile(projectPath, project.replace(
    'CODE_SIGN_ENTITLEMENTS: Config/TaisaPersonal.entitlements',
    'CODE_SIGN_ENTITLEMENTS: Config/TaisaPersonal.entitlements\n      configs:\n        Personal:\n          CODE_SIGN_ENTITLEMENTS: Config/TaisaPersonal.entitlements',
  ));
  assert.deepEqual(await verifyNativeProject(fixture), []);
  for (const mutation of [
    project.replace('PRODUCT_NAME: TaisaPersonal', 'PRODUCT_NAME: TaisaPersonal\n        UIBackgroundModes: [remote-notification]'),
    project.replace('PRODUCT_BUNDLE_IDENTIFIER: com.taisa.app.personal', 'PRODUCT_BUNDLE_IDENTIFIER: com.taisa.app'),
    project.replace('  TaisaPersonalTests:', '      - package: TaisaFoundation\n        product: TaisaCloudKit\n  TaisaPersonalTests:'),
    project.replace('  Taisa-Personal:\n', '  Taisa-Personal:\n    archive:\n      config: Personal\n'),
    project.replace('CODE_SIGN_ENTITLEMENTS: Config/TaisaPersonal.entitlements', 'CODE_SIGN_ENTITLEMENTS: Config/TaisaDev.entitlements'),
    project.replace('CODE_SIGN_ENTITLEMENTS: Config/TaisaPersonal.entitlements', 'CODE_SIGN_ENTITLEMENTS: Config/TaisaPersonal.entitlements\n      configs:\n        Personal:\n          CODE_SIGN_ENTITLEMENTS: Config/TaisaDev.entitlements'),
    project.replace('CODE_SIGN_ENTITLEMENTS: Config/TaisaPersonal.entitlements', 'CODE_SIGN_ENTITLEMENTS: Config/TaisaPersonal.entitlements\n      configs:\n        Personal:\n          PRODUCT_BUNDLE_IDENTIFIER: com.taisa.app'),
    project.replace('CODE_SIGN_ENTITLEMENTS: Config/TaisaPersonal.entitlements', 'CODE_SIGN_ENTITLEMENTS: Config/TaisaPersonal.entitlements\n      configs:\n        Personal:\n          TAISA_ENVIRONMENT: development'),
    project.replace('CODE_SIGN_ENTITLEMENTS: Config/TaisaPersonal.entitlements', 'CODE_SIGN_ENTITLEMENTS: Config/TaisaPersonal.entitlements\n      configs:\n        Debug:\n          CODE_SIGN_ENTITLEMENTS: Config/TaisaDev.entitlements'),
    project.replace('CODE_SIGN_ENTITLEMENTS: Config/TaisaPersonal.entitlements', 'CODE_SIGN_ENTITLEMENTS: Config/TaisaPersonal.entitlements\n      configs:\n        Personal:\n          CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]: Config/TaisaDev.entitlements'),
  ]) {
    await writeFile(projectPath, mutation);
    assert.ok((await verifyNativeProject(fixture)).includes('Personal app isolation mismatch'));
    assert.equal((await inspectNativeProject(fixture)).previewArchiveEnabled, false);
  }
  const after = await Promise.all(liveNames.map((name) => readFile(join(fixture, `apple/Config/${name}.entitlements`))));
  assert.deepEqual(after, before);
});

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
    'TaisaHome',
    'TaisaStorage',
    'TaisaCloudKit',
    'TaisaRecovery',
    'TaisaSecurity',
    'TaisaVoice',
    'TaisaConversations',
    'TaisaAudio',
    'TaisaNetworking',
  ]);
  assert.deepEqual(result.previewProducts, [
    'TaisaCore',
    'TaisaContracts',
    'TaisaDesignSystem',
    'TaisaHome',
    'TaisaPreviewSupport',
    'TaisaStorage',
    'TaisaVoice',
    'TaisaConversations',
  ]);
});

test('preview includes the shared conversation entry contract', async () => {
  const project = await readFile(join(repositoryRoot, 'apple/project.yml'), 'utf8');
  const preview = project.slice(project.indexOf('  TaisaPreview:'), project.indexOf('  TaisaUnitTests:'));
  assert.match(preview, /TaisaApp\/AppShell\/PrimaryDestination\.swift/);
});

test('CloudKit capability is isolated to development and production identities', async () => {
  const result = await inspectNativeProject(repositoryRoot);
  assert.deepEqual(result.cloudKitIsolation, {
    developmentContainer: 'iCloud.com.taisa.app.dev',
    productionContainer: 'iCloud.com.taisa.app',
    developmentContainers: ['iCloud.com.taisa.app.dev'],
    productionContainers: ['iCloud.com.taisa.app'],
    developmentCloudEnvironment: 'Development',
    productionCloudEnvironment: 'Production',
    previewContainers: [],
    previewServices: [],
    previewPushEnvironment: null,
    previewLinksLiveTransport: false,
    developmentPushEnvironment: 'development',
    productionPushEnvironment: 'production',
    developmentServices: ['CloudKit'],
    productionServices: ['CloudKit'],
    associatedDomains: false,
    projectEntitlementBindings: { development: true, production: true, preview: true },
  });
});

test('background remote notifications are configured only for the live app target', async () => {
  const result = await inspectNativeProject(repositoryRoot);
  assert.deepEqual(result.backgroundNotificationIsolation, {
    liveModes: ['remote-notification'],
    liveInfoBound: true,
    previewConfiguresBackgroundMode: false,
  });
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
  const designSystemWorkflow = await readFile(
    resolve(repositoryRoot, '.github/workflows/design-system.yml'),
    'utf8',
  );
  const combinedScript = await readFile(
    resolve(repositoryRoot, 'scripts/native-apple/verify-all.sh'),
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
    'Taisa-Personal',
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
    'for attempt in 1 2 3',
    'brew install ripgrep',
    '2.46.0',
    'verify:native-apple:all',
    'upload-artifact',
  ]) assert.match(workflow, new RegExp(required.replaceAll('.', '\\.')));

  assert.match(designSystemWorkflow, /name: Design System Compliance/);
  assert.match(designSystemWorkflow, /npm run verify:native-design-system/);
  for (const bundleIdentifier of [
    'com.taisa.app.dev',
    'com.taisa.app.preview',
    'com.taisa.app.personal',
  ]) {
    assert.match(combinedScript, new RegExp(`simctl uninstall.*${bundleIdentifier}`));
  }
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

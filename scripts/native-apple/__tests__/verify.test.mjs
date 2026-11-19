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
import { validatePullRequestContract } from '../validate-pr-contract.mjs';

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
    filter: (source) => !source.includes('/Packages/'),
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
    project.replace('  TaisaPersonalTests:', '      - sdk: CloudKit.framework\n  TaisaPersonalTests:'),
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

test('personal builds cannot silently drop the approved voice gateway', async () => {
  const fixture = await mkdtemp(join(tmpdir(), 'taisa-personal-gateway-'));
  await cp(resolve(repositoryRoot, 'apple'), join(fixture, 'apple'), {
    recursive: true,
    filter: (source) => !source.includes('/Packages/'),
  });
  assert.deepEqual(await verifyNativeProject(fixture), []);

  const configPath = join(fixture, 'apple/Config/Personal.xcconfig');
  const config = await readFile(configPath, 'utf8');
  await writeFile(
    configPath,
    config.replace(
      'TAISA_VOICE_GATEWAY_URL = https:/$()/taisa-production.up.railway.app',
      'TAISA_VOICE_GATEWAY_URL =',
    ),
  );

  assert.ok(
    (await verifyNativeProject(fixture))
      .includes('Personal voice gateway configuration mismatch'),
  );
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
    'TaisaCareerWork',
    'TaisaYou',
    'TaisaStorage',
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
    'TaisaCareerWork',
    'TaisaYou',
    'TaisaPreviewSupport',
    'TaisaStorage',
    'TaisaVoice',
    'TaisaAudio',
    'TaisaConversations',
  ]);
});

test('preview includes the shared conversation entry contract', async () => {
  const project = await readFile(join(repositoryRoot, 'apple/project.yml'), 'utf8');
  const preview = project.slice(project.indexOf('  TaisaPreview:'), project.indexOf('  TaisaUnitTests:'));
  assert.match(preview, /TaisaApp\/AppShell\/PrimaryDestination\.swift/);
});

test('shipping identities contain no CloudKit or push capability', async () => {
  const result = await inspectNativeProject(repositoryRoot);
  assert.deepEqual(result.cloudKitIsolation, {
    developmentContainer: null,
    productionContainer: null,
    developmentContainers: [],
    productionContainers: [],
    developmentCloudEnvironment: null,
    productionCloudEnvironment: null,
    previewContainers: [],
    previewServices: [],
    previewPushEnvironment: null,
    previewLinksLiveTransport: false,
    developmentPushEnvironment: null,
    productionPushEnvironment: null,
    developmentServices: [],
    productionServices: [],
    associatedDomains: false,
    projectEntitlementBindings: { development: true, production: true, preview: true },
  });
});

test('shipping targets contain no remote-notification background mode', async () => {
  const result = await inspectNativeProject(repositoryRoot);
  assert.deepEqual(result.backgroundNotificationIsolation, {
    liveModes: [],
    liveInfoBound: true,
    previewConfiguresBackgroundMode: false,
  });
});

test('generated project and source configuration enforce iPhone-only support', async () => {
  const result = await inspectNativeProject(repositoryRoot);
  assert.deepEqual(result.iphoneOnlySupport, {
    projectDeviceFamily: true,
    baseDeviceFamily: true,
    generatedDeviceFamily: true,
    hasIPadOrientation: false,
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
    assert.match(combinedScript, new RegExp(`reset_simulator_app.*${bundleIdentifier}`));
  }
  assert.match(combinedScript, /reset_simulator_app\(\)/);
  assert.equal(
    [...combinedScript.matchAll(/reset_simulator_app "\$\{iphone_name\}" com\.taisa\.app\.(?:dev|preview|personal)/g)].length,
    3,
  );
  assert.doesNotMatch(combinedScript, /iPad|TAISA_IPAD|ipad_name/);
  const resetBody = combinedScript.match(/reset_simulator_app\(\) \{([\s\S]*?)\n\}/)?.[1] ?? '';
  assert.match(resetBody, /simctl boot /);
  assert.match(resetBody, /simctl bootstatus .* -b/);
  assert.ok(resetBody.indexOf('simctl bootstatus') < resetBody.indexOf('simctl uninstall'));
});

test('native CI risk classification fails closed for sensitive production paths', () => {
  const classify = (paths) => execFileSync(
    'bash',
    [resolve(repositoryRoot, 'scripts/native-apple/classify-ci-risk.sh')],
    { encoding: 'utf8', input: `${paths.join('\n')}\n` },
  );

  assert.match(classify(['apple/TaisaApp/Home/HomeView.swift']), /native_required=true/);
  assert.match(classify(['apple/TaisaApp/Home/HomeView.swift']), /high_risk_required=false/);
  assert.match(classify(['apple/TaisaApp/Home/HomeView.swift']), /detected_risks=ui/);
  assert.match(classify(['apple/TaisaApp/Home/HomeView.swift']), /app_compile_required=true/);
  assert.match(classify(['.github/workflows/native-fast.yml']), /app_compile_required=false/);
  assert.match(
    classify(['scripts/native-apple/__tests__/verify.test.mjs']),
    /app_compile_required=false/,
  );
  assert.match(
    classify([
      'apple/Packages/TaisaFoundation/Sources/TaisaAudio/AudioCaptureService.swift',
      'apple/Packages/TaisaFoundation/Sources/TaisaStorage/TaisaMigrator.swift',
    ]),
    /detected_risks=device,data/,
  );
  assert.match(
    classify([
      'apple/TaisaApp/Home/HomeView.swift',
      'apple/Packages/TaisaFoundation/Sources/TaisaCore/AppClock.swift',
    ]),
    /detected_risks=logic,ui/,
  );
  for (const path of [
    '.github/workflows/native-apple.yml',
    '.github/workflows/native-apple.test.yml',
    'railway.json',
    'package.json',
    'apple/Packages/TaisaFoundation/Package.swift',
    'apple/Packages/TaisaFoundation/Package.resolved',
    'apple/project.yml',
    'scripts/native-apple/verify-selected.sh',
    'scripts/native-apple/verify-xcode-selected.sh',
    'apple/Config/Personal.xcconfig',
    'apple/Config/TaisaPersonal.entitlements',
    'apple/Packages/TaisaFoundation/Sources/TaisaStorage/TaisaMigrator.swift',
    'apple/Packages/TaisaFoundation/Sources/TaisaSecurity/RecoveryKey.swift',
    'apple/Packages/TaisaFoundation/Sources/TaisaVoice/VoiceGatewayCredentialStore.swift',
    'apple/Packages/TaisaFoundation/Sources/TaisaRecovery/RestoreCoordinator.swift',
    'apple/TaisaApp/Recovery/PersonalRecoveryBackend.swift',
    'backend/src/db/schema.sql',
    'backend/src/auth/deviceCredentials.ts',
    'backend/src/config/production.ts',
    'mobile/src/db/migrations.ts',
    'scripts/verify-branch-topology.sh',
  ]) {
    assert.match(classify([path]), /native_required=true/, path);
    assert.match(classify([path]), /high_risk_required=true/, path);
  }
  assert.match(
    classify(['apple/Packages/TaisaFoundation/Tests/TaisaStorageTests/TaisaMigratorTests.swift']),
    /high_risk_required=false/,
  );
  assert.match(
    classify(['scripts/native-apple/__tests__/verify.test.mjs']),
    /high_risk_required=false/,
  );
  assert.match(
    classify(['apple/Packages/TaisaFoundation/Tests/TaisaStorageTests/TaisaMigratorTests.swift']),
    /native_required=true/,
  );
  assert.match(classify(['backend/src/__tests__/coaching.streaming.test.ts']), /backend_required=true/);
  assert.match(classify(['backend/src/routes/coaching.ts']), /backend_required=true/);
  for (const path of [
    'shared/fixtures/transcription/completed.valid.json',
    'shared/fixtures/coaching-stream/completed.valid.json',
    'scripts/native-contracts/verify-transcription-fixtures.mjs',
  ]) {
    assert.match(classify([path]), /native_required=true/, path);
  }
  for (const path of [
    'docs/agents/issue-tracker.md',
    '.agents/skills/taisa-workflow/templates/bounded-goal.md',
    'docs/project-memory.md',
    'CLAUDE.md',
  ]) {
    assert.match(classify([path]), /detected_risks=workflow/, path);
  }
  for (const [path, target] of [
    ['apple/TaisaPersonalTests/PersonalIsolationTests.swift', 'TaisaPersonalTests'],
    ['apple/TaisaPersonalUITests/PersonalRecoveryUITests.swift', 'TaisaPersonalUITests'],
    ['apple/TaisaUnitTests/AppRuntimeTests.swift', 'TaisaUnitTests'],
    ['apple/TaisaUITests/TaisaLaunchTests.swift', 'TaisaUITests'],
    ['apple/TaisaPreviewUITests/TaisaPreviewCatalogTests.swift', 'TaisaPreviewUITests'],
  ]) {
    assert.match(classify([path]), new RegExp(`xcode_test_targets=${target}`), path);
  }
});

test('pull request contract requires one tracer, one outcome, additive risks, and exact device evidence', () => {
  const validBody = `## Linear tracer

APF-96

## Reviewable outcome

Route one device-sensitive pull request through focused verification.

## Declared risks

- [x] device
- [x] workflow

## Device QA evidence

Device: iPhone 17 Pro
Operating system: iOS 26.1
Behavior: audio capture interruption recovery
Result: passed
Exact commit: abc123

## Override

None.`;
  assert.deepEqual(validatePullRequestContract({
    body: validBody,
    detectedRisks: ['device', 'workflow'],
    headSha: 'abc123',
  }), {
    declaredRisks: ['device', 'workflow'],
    errors: [],
    tracer: 'APF-96',
  });

  const invalid = validatePullRequestContract({
    body: '## Reviewable outcome\n\nDescribe the one result that this pull request delivers.\n\n- [x] ui',
    detectedRisks: ['security'],
    headSha: 'def456',
  });
  assert.match(invalid.errors.join('\n'), /Linear tracer/);
  assert.match(invalid.errors.join('\n'), /reviewable outcome/);
  assert.match(invalid.errors.join('\n'), /security/);

  const multipleTracers = validatePullRequestContract({
    body: validBody.replace('APF-96', 'APF-96 and APF-97'),
    detectedRisks: ['device', 'workflow'],
    headSha: 'abc123',
  });
  assert.match(multipleTracers.errors.join('\n'), /exactly one APF Linear tracer/);
});

test('tiered native CI uses focused pull-request checks and reserves full verification for release or manual runs', async () => {
  const packageJSON = JSON.parse(await readFile(resolve(repositoryRoot, 'package.json'), 'utf8'));
  const fastScript = await readFile(
    resolve(repositoryRoot, 'scripts/native-apple/verify-fast.sh'),
    'utf8',
  );
  const fastWorkflow = await readFile(
    resolve(repositoryRoot, '.github/workflows/native-fast.yml'),
    'utf8',
  );
  const fullWorkflow = await readFile(
    resolve(repositoryRoot, '.github/workflows/native-apple.yml'),
    'utf8',
  );
  const trustedPolicy = await readFile(
    resolve(repositoryRoot, '.github/workflows/pr-policy.yml'),
    'utf8',
  );
  const selectedScript = await readFile(
    resolve(repositoryRoot, 'scripts/native-apple/verify-selected.sh'),
    'utf8',
  );
  const selectedXcodeTests = await readFile(
    resolve(repositoryRoot, 'scripts/native-apple/verify-xcode-selected.sh'),
    'utf8',
  );

  assert.match(packageJSON.scripts['verify:native-apple:fast'], /verify-fast\.sh/);
  for (const required of [
    'verify-generated-project.sh',
    'generate-build-metadata.sh',
    'verify:native-contracts',
    'swift test',
    'verify:native-design-system',
    'verify:workflow',
  ]) assert.match(fastScript, new RegExp(required.replaceAll('.', '\\.')));
  assert.doesNotMatch(fastScript, /xcodebuild (test|build|build-for-testing)/);

  assert.match(fastWorkflow, /name: Native Fast Checks/);
  assert.match(fastWorkflow, /pull_request:/);
  assert.match(fastWorkflow, /types: \[opened, reopened, synchronize, edited\]/);
  assert.doesNotMatch(fastWorkflow, /edited, labeled/);
  assert.match(fastWorkflow, /branches: \[main\]/);
  assert.match(fastWorkflow, /verify:native-apple:fast/);
  assert.match(fastWorkflow, /validate-pr-contract\.mjs/);
  assert.match(fastWorkflow, /PR_CONTRACT_MODE: report/);
  assert.match(fastWorkflow, /detected_risks/);
  assert.match(fastWorkflow, /verify-selected\.sh/);
  assert.match(fastWorkflow, /backend_required/);
  assert.match(fastWorkflow, /app_compile_required/);
  assert.match(fastWorkflow, /xcode_test_targets/);
  assert.match(fastWorkflow, /verify-xcode-selected\.sh/);
  assert.match(fastWorkflow, /name: Install pinned iOS platform/);
  assert.match(fastWorkflow, /xcodebuild -downloadPlatform iOS/);
  assert.match(fastWorkflow, /for attempt in 1 2 3/);
  assert.match(fastWorkflow, /npm run build --workspace=backend/);
  assert.match(fastWorkflow, /npm test --workspace=backend -- --runInBand/);

  assert.match(selectedScript, /scheme Taisa-Personal/);
  assert.match(selectedScript, /test "\$1" = workflow/);
  assert.match(selectedScript, /No Product app compile is required for a workflow-only change/);
  assert.match(selectedScript, /generic\/platform=iOS Simulator/);
  assert.match(selectedScript, /\*,ui,\*/);
  assert.match(selectedScript, /scheme Taisa-Preview/);
  assert.match(selectedScript, /\*,device,\*/);
  assert.match(selectedScript, /generic\/platform=iOS'/);

  for (const target of [
    'TaisaPersonalTests',
    'TaisaPersonalUITests',
    'TaisaUnitTests',
    'TaisaUITests',
    'TaisaPreviewUITests',
  ]) assert.match(selectedXcodeTests, new RegExp(target));
  assert.match(selectedXcodeTests, /xcodebuild test/);
  assert.match(selectedXcodeTests, /-only-testing:/);

  assert.match(trustedPolicy, /pull_request_target:/);
  assert.match(trustedPolicy, /types: \[opened, reopened, synchronize, edited\]/);
  assert.match(trustedPolicy, /ref: \$\{\{ github\.event\.pull_request\.base\.sha \}\}/);
  assert.doesNotMatch(trustedPolicy, /ref:.*head\.sha/);
  assert.match(trustedPolicy, /Never check out or execute candidate code/);
  assert.match(trustedPolicy, /PR_CONTRACT_MODE: report/);
  assert.match(trustedPolicy, /validate-pr-contract\.mjs/);
  assert.match(fastWorkflow, /native-fast-\$\{\{/);
  assert.match(fastWorkflow, /cancel-in-progress: true/);

  assert.match(fullWorkflow, /name: Native Apple Full Verification/);
  assert.doesNotMatch(fullWorkflow, /pull_request:/);
  assert.doesNotMatch(fullWorkflow, /schedule:/);
  assert.match(fullWorkflow, /workflow_dispatch:/);
  assert.doesNotMatch(fullWorkflow, /branches: \[main\]/);
  assert.match(fullWorkflow, /tags: \['v\*'\]/);
  assert.doesNotMatch(fullWorkflow, /merge-ready/);
  assert.doesNotMatch(fullWorkflow, /name: Native Merge Gate/);
  assert.doesNotMatch(fullWorkflow, /name: Classify native impact and risk/);
  assert.doesNotMatch(fullWorkflow, /native_required/);
  assert.doesNotMatch(fullWorkflow, /high_risk_required/);
  assert.doesNotMatch(fullWorkflow, /github\.event\.pull_request/);
  assert.doesNotMatch(fullWorkflow, /scripts\/native-apple\/classify-ci-risk\.sh/);
  assert.doesNotMatch(fullWorkflow, /actions\/github-script@v7/);
  assert.equal(
    fullWorkflow.match(/^concurrency:/gm)?.length,
    1,
    'full native workflow must declare exactly one top-level concurrency policy',
  );
  assert.match(fullWorkflow, /cancel-in-progress: true/);
  assert.match(fullWorkflow, /npm run verify:native-apple:all/);
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

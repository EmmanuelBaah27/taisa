import { readdir, readFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

function valueFor(contents, key) {
  const match = contents.match(new RegExp(`^${key}\\s*=\\s*(.+)$`, 'm'));
  return match?.[1]?.trim() ?? null;
}

function targetBlock(project, targetName) {
  const start = project.indexOf(`  ${targetName}:\n`);
  if (start === -1) return '';
  const remainder = project.slice(start + `  ${targetName}:\n`.length);
  const end = remainder.search(/^  \S[^\n]*:\s*$|^\S[^\n]*:\s*$/m);
  return `  ${targetName}:\n${end === -1 ? remainder : remainder.slice(0, end)}`;
}

function packageProducts(block) {
  return [...block.matchAll(/^\s+product:\s+(.+)$/gm)].map((match) => match[1].trim());
}

function settingScopes(settings = {}) {
  return [settings.base ?? settings, ...Object.values(settings.configs ?? {})];
}

function personalSettings(settings = {}) {
  return { ...(settings.base ?? settings), ...(settings.configs?.Personal ?? {}) };
}

function personalBinding(settings, key, expected) {
  // Every configuration of this isolated app must retain the same binding,
  // including SDK-conditional overrides that can affect an unsigned device build.
  return settingScopes(settings).every((scope) => Object.entries(scope).every(([name, value]) => (
    (name !== key && !name.startsWith(`${key}[`)) || value === expected
  )));
}

const PRODUCTION_PREVIEW_PATTERNS = [
  'PreviewSupport',
  'TaisaPreview',
  'com.taisa.app.preview',
  'foundation.accessibility-text',
  'foundation.default',
  'foundation.diagnostics',
  'foundation.increased-contrast',
  'foundation.narrow-ipad',
  'foundation.reduced-motion',
];

async function bundleEntries(root) {
  const entries = await readdir(root, { withFileTypes: true });
  const nested = await Promise.all(entries.map(async (entry) => {
    const target = resolve(root, entry.name);
    if (entry.isDirectory()) return bundleEntries(target);
    return entry.isFile() ? [target] : [];
  }));
  return nested.flat();
}

export async function inspectProductionBundle(bundlePath) {
  const matches = new Set();
  for (const file of await bundleEntries(bundlePath)) {
    const contents = await readFile(file);
    for (const pattern of PRODUCTION_PREVIEW_PATTERNS) {
      if (file.includes(pattern) || contents.includes(Buffer.from(pattern))) {
        matches.add(pattern);
      }
    }
  }
  return PRODUCTION_PREVIEW_PATTERNS.filter((pattern) => matches.has(pattern));
}

export async function inspectPersonalBundle(bundlePath) {
  const errors = [];
  const info = JSON.parse(execFileSync('plutil', [
    '-convert', 'json', '-o', '-', resolve(bundlePath, 'Info.plist'),
  ], { encoding: 'utf8' }));
  if (info.CFBundleIdentifier !== 'com.taisa.app.personal' || info.TaisaEnvironment !== 'personal') {
    errors.push('Personal bundle identity or environment mismatch');
  }
  if ('UIBackgroundModes' in info) errors.push('Personal bundle declares background modes');
  const patterns = ['TaisaCloudKit', 'CKContainer', 'CloudKit.framework'];
  const matches = new Set();
  for (const file of await bundleEntries(bundlePath)) {
    const contents = await readFile(file);
    for (const pattern of patterns) {
      if (file.includes(pattern) || contents.includes(Buffer.from(pattern))) matches.add(pattern);
    }
  }
  for (const pattern of patterns.filter((pattern) => matches.has(pattern))) {
    errors.push(`Personal bundle contains live CloudKit reference: ${pattern}`);
  }
  return errors;
}

export function unresolvedBuildIdentityPlaceholders(contents) {
  const placeholders = [
    /\$\([^)]+\)/g,
    /GIT_(?:COMMIT|BRANCH)/g,
    /BUILD_(?:NUMBER|IDENTITY)/g,
  ];
  return [...new Set(placeholders.flatMap((pattern) => contents.match(pattern) ?? []))].sort();
}

export async function inspectNativeProject(repositoryRoot) {
  const appleRoot = resolve(repositoryRoot, 'apple');
  const [project, debugConfig, previewConfig, releaseConfig, personalConfig] = await Promise.all([
    readFile(resolve(appleRoot, 'project.yml'), 'utf8'),
    readFile(resolve(appleRoot, 'Config/Debug.xcconfig'), 'utf8'),
    readFile(resolve(appleRoot, 'Config/Preview.xcconfig'), 'utf8'),
    readFile(resolve(appleRoot, 'Config/Release.xcconfig'), 'utf8'),
    readFile(resolve(appleRoot, 'Config/Personal.xcconfig'), 'utf8'),
  ]);

  const productionBlock = targetBlock(project, 'Taisa');
  const previewTargetBlock = targetBlock(project, 'TaisaPreview');
  const personalBlock = targetBlock(project, 'TaisaPersonal');
  const specification = JSON.parse(execFileSync('xcodegen', [
    'dump', '--no-env', '--type', 'json', '--spec', resolve(appleRoot, 'project.yml'),
  ], { encoding: 'utf8' }));
  const targetSettings = specification.targets?.TaisaPersonal?.settings ?? {};
  const effectivePersonalSettings = {
    ...personalSettings(specification.settings),
    ...personalSettings(targetSettings),
  };
  const personalScheme = targetBlock(project, 'Taisa-Personal');
  const previewScheme = targetBlock(project, 'Taisa-Preview');
  const leakPatterns = ['TaisaPreview', 'PreviewSupport', 'com.taisa.app.preview'];
  const entitlement = (name) => JSON.parse(execFileSync('plutil', [
    '-convert', 'json', '-o', '-', resolve(appleRoot, `Config/${name}.entitlements`),
  ], { encoding: 'utf8' }));
  const [developmentRights, productionRights, previewRights] = [
    entitlement('TaisaDev'), entitlement('Taisa'), entitlement('TaisaPreview'),
  ];
  const liveInfo = JSON.parse(execFileSync('plutil', [
    '-convert', 'json', '-o', '-', resolve(appleRoot, 'Config/TaisaInfo.plist'),
  ], { encoding: 'utf8' }));
  const productionProducts = packageProducts(productionBlock);
  const previewProducts = packageProducts(previewTargetBlock);
  const selectedEntitlements = effectivePersonalSettings.CODE_SIGN_ENTITLEMENTS;
  const personalRights = typeof selectedEntitlements === 'string'
    ? JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', resolve(appleRoot, selectedEntitlements)], { encoding: 'utf8' }))
    : {};
  const personalInfoPath = personalBlock.match(/info:\s*\n\s*path:\s*(.+)/)?.[1]?.trim();
  const personalInfo = personalInfoPath
    ? JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', resolve(appleRoot, personalInfoPath)], { encoding: 'utf8' }))
    : {};

  return {
    personalIsolation: {
      personal: {
        bundleIdentifier: valueFor(personalConfig, 'PRODUCT_BUNDLE_IDENTIFIER'),
        entitlementKeys: Object.keys(personalRights).sort(),
        linksLiveTransport: /TaisaCloudKit|CloudKit\.framework/.test(personalBlock),
        configuresBackgroundMode: /UIBackgroundModes|remote-notification/.test(personalBlock)
          || 'UIBackgroundModes' in personalInfo,
        archiveEnabled: /\n\s+archive:|\n\s+- archive\s*$|TaisaPersonal:\s+all/m.test(personalScheme),
      },
    },
    personalProjectBindings: {
      app: personalBlock.includes('type: application'),
      identity: effectivePersonalSettings.PRODUCT_BUNDLE_IDENTIFIER === 'com.taisa.app.personal'
        && personalBinding(targetSettings, 'PRODUCT_BUNDLE_IDENTIFIER', 'com.taisa.app.personal'),
      environment: effectivePersonalSettings.TAISA_ENVIRONMENT === 'personal'
        && personalBinding(targetSettings, 'TAISA_ENVIRONMENT', 'personal')
        && valueFor(personalConfig, 'TAISA_ENVIRONMENT') === 'personal',
      condition: personalBlock.includes('TAISA_PERSONAL') && personalConfig.includes('TAISA_PERSONAL'),
      entitlements: selectedEntitlements === 'Config/TaisaPersonal.entitlements'
        && personalBinding(targetSettings, 'CODE_SIGN_ENTITLEMENTS', 'Config/TaisaPersonal.entitlements'),
      configuration: /Personal:\s*Config\/Personal\.xcconfig/.test(project),
      testHost: /target:\s*TaisaPersonal\s*$/m.test(targetBlock(project, 'TaisaPersonalTests')),
      scheme: /config:\s*Personal/.test(personalScheme) && personalScheme.includes('- TaisaPersonalTests'),
    },
    bundleIdentifiers: {
      production: valueFor(releaseConfig, 'PRODUCT_BUNDLE_IDENTIFIER'),
      development: valueFor(debugConfig, 'PRODUCT_BUNDLE_IDENTIFIER'),
      preview: valueFor(previewConfig, 'PRODUCT_BUNDLE_IDENTIFIER'),
    },
    productionPreviewLeaks: leakPatterns.filter((pattern) => productionBlock.includes(pattern)),
    previewArchiveEnabled: /\n\s+archive:/.test(previewScheme)
      || /\n\s+- archive\s*$/.test(previewScheme),
    testTargets: ['TaisaUnitTests', 'TaisaUITests'].filter((name) => (
      project.includes(`  ${name}:\n`)
    )),
    productionProducts,
    previewProducts,
    cloudKitIsolation: {
      developmentContainer: developmentRights['com.apple.developer.icloud-container-identifiers']?.[0] ?? null,
      productionContainer: productionRights['com.apple.developer.icloud-container-identifiers']?.[0] ?? null,
      developmentContainers: developmentRights['com.apple.developer.icloud-container-identifiers'] ?? [],
      productionContainers: productionRights['com.apple.developer.icloud-container-identifiers'] ?? [],
      developmentCloudEnvironment: developmentRights['com.apple.developer.icloud-container-environment'] ?? null,
      productionCloudEnvironment: productionRights['com.apple.developer.icloud-container-environment'] ?? null,
      previewContainers: previewRights['com.apple.developer.icloud-container-identifiers'] ?? [],
      previewServices: previewRights['com.apple.developer.icloud-services'] ?? [],
      previewPushEnvironment: previewRights['aps-environment'] ?? null,
      previewLinksLiveTransport: previewProducts.includes('TaisaCloudKit'),
      developmentPushEnvironment: developmentRights['aps-environment'] ?? null,
      productionPushEnvironment: productionRights['aps-environment'] ?? null,
      developmentServices: developmentRights['com.apple.developer.icloud-services'] ?? [],
      productionServices: productionRights['com.apple.developer.icloud-services'] ?? [],
      associatedDomains: [developmentRights, productionRights, previewRights]
        .some((rights) => 'com.apple.developer.associated-domains' in rights),
      projectEntitlementBindings: {
        development: /Debug:\s*\n\s*CODE_SIGN_ENTITLEMENTS:\s*Config\/TaisaDev\.entitlements/.test(productionBlock),
        production: /Release:\s*\n\s*CODE_SIGN_ENTITLEMENTS:\s*Config\/Taisa\.entitlements/.test(productionBlock),
        preview: /CODE_SIGN_ENTITLEMENTS:\s*Config\/TaisaPreview\.entitlements/.test(previewTargetBlock),
      },
    },
    backgroundNotificationIsolation: {
      liveModes: liveInfo.UIBackgroundModes ?? [],
      liveInfoBound: /info:\s*\n\s*path:\s*Config\/TaisaInfo\.plist/.test(productionBlock),
      previewConfiguresBackgroundMode: /UIBackgroundModes|remote-notification/.test(previewTargetBlock),
    },
  };
}

export async function verifyNativeProject(repositoryRoot, productionBundle, personalBundle) {
  const inspected = await inspectNativeProject(repositoryRoot);
  const errors = [];
  const expected = {
    production: 'com.taisa.app',
    development: 'com.taisa.app.dev',
    preview: 'com.taisa.app.preview',
  };

  if (JSON.stringify(inspected.bundleIdentifiers) !== JSON.stringify(expected)) {
    errors.push(`Unexpected bundle identifiers: ${JSON.stringify(inspected.bundleIdentifiers)}`);
  }
  for (const leak of inspected.productionPreviewLeaks) {
    errors.push(`Production target contains preview reference: ${leak}`);
  }
  if (productionBundle) {
    for (const leak of await inspectProductionBundle(productionBundle)) {
      errors.push(`Production bundle contains preview reference: ${leak}`);
    }
  }
  if (personalBundle) errors.push(...await inspectPersonalBundle(personalBundle));
  const metadataPath = resolve(
    repositoryRoot,
    'apple/Generated/BuildMetadata.generated.swift',
  );
  try {
    const placeholders = unresolvedBuildIdentityPlaceholders(
      await readFile(metadataPath, 'utf8'),
    );
    for (const placeholder of placeholders) {
      errors.push(`Build identity contains unresolved placeholder: ${placeholder}`);
    }
  } catch {
    errors.push('Generated build identity is missing');
  }
  if (inspected.previewArchiveEnabled) errors.push('Preview scheme enables archive');
  const personal = inspected.personalIsolation.personal;
  if (personal.bundleIdentifier !== 'com.taisa.app.personal'
      || personal.entitlementKeys.length !== 0 || personal.linksLiveTransport
      || personal.configuresBackgroundMode || personal.archiveEnabled
      || Object.values(inspected.personalProjectBindings).some((bound) => !bound)) {
    errors.push('Personal app isolation mismatch');
  }
  const isolation = inspected.cloudKitIsolation;
  if (isolation.developmentContainer !== 'iCloud.com.taisa.app.dev'
      || isolation.productionContainer !== 'iCloud.com.taisa.app'
      || JSON.stringify(isolation.developmentContainers) !== '["iCloud.com.taisa.app.dev"]'
      || JSON.stringify(isolation.productionContainers) !== '["iCloud.com.taisa.app"]'
      || isolation.developmentCloudEnvironment !== 'Development'
      || isolation.productionCloudEnvironment !== 'Production'
      || isolation.previewContainers.length !== 0
      || isolation.previewServices.length !== 0
      || isolation.previewPushEnvironment !== null
      || isolation.previewLinksLiveTransport
      || isolation.developmentPushEnvironment !== 'development'
      || isolation.productionPushEnvironment !== 'production'
      || JSON.stringify(isolation.developmentServices) !== '["CloudKit"]'
      || JSON.stringify(isolation.productionServices) !== '["CloudKit"]'
      || isolation.associatedDomains
      || Object.values(isolation.projectEntitlementBindings).some((bound) => !bound)) {
    errors.push('CloudKit capability or entitlement isolation mismatch');
  }
  const background = inspected.backgroundNotificationIsolation;
  if (JSON.stringify(background.liveModes) !== '["remote-notification"]'
      || !background.liveInfoBound || background.previewConfiguresBackgroundMode) {
    errors.push('Remote-notification background mode must belong only to live app targets');
  }
  return errors;
}

const isMain = process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1]);
if (isMain) {
  const repositoryRoot = resolve(import.meta.dirname, '../..');
  const errors = await verifyNativeProject(
    repositoryRoot,
    process.env.TAISA_PRODUCTION_BUNDLE,
    process.env.TAISA_PERSONAL_BUNDLE,
  );
  if (errors.length) {
    console.error(errors.join('\n'));
    process.exitCode = 1;
  } else {
    console.log('Native Apple isolation verification passed.');
  }
}

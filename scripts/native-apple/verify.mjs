import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

function valueFor(contents, key) {
  const match = contents.match(new RegExp(`^${key}\\s*=\\s*(.+)$`, 'm'));
  return match?.[1]?.trim() ?? null;
}

function targetBlock(project, targetName, nextTargetName) {
  const start = project.indexOf(`  ${targetName}:\n`);
  if (start === -1) return '';
  const endMarker = nextTargetName ? `  ${nextTargetName}:\n` : '\nschemes:\n';
  const end = project.indexOf(endMarker, start + targetName.length + 3);
  return project.slice(start, end === -1 ? project.length : end);
}

export async function inspectNativeProject(repositoryRoot) {
  const appleRoot = resolve(repositoryRoot, 'apple');
  const [project, debugConfig, previewConfig, releaseConfig] = await Promise.all([
    readFile(resolve(appleRoot, 'project.yml'), 'utf8'),
    readFile(resolve(appleRoot, 'Config/Debug.xcconfig'), 'utf8'),
    readFile(resolve(appleRoot, 'Config/Preview.xcconfig'), 'utf8'),
    readFile(resolve(appleRoot, 'Config/Release.xcconfig'), 'utf8'),
  ]);

  const productionBlock = targetBlock(project, 'Taisa', 'TaisaPreview');
  const previewStart = project.indexOf('  Taisa-Preview:\n');
  const previewEnd = project.indexOf('  Taisa:\n', previewStart);
  const previewScheme = project.slice(previewStart, previewEnd);
  const leakPatterns = ['TaisaPreview', 'PreviewSupport', 'com.taisa.app.preview'];

  return {
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
  };
}

export async function verifyNativeProject(repositoryRoot) {
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
  if (inspected.previewArchiveEnabled) errors.push('Preview scheme enables archive');
  return errors;
}

const isMain = process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1]);
if (isMain) {
  const repositoryRoot = resolve(import.meta.dirname, '../..');
  const errors = await verifyNativeProject(repositoryRoot);
  if (errors.length) {
    console.error(errors.join('\n'));
    process.exitCode = 1;
  } else {
    console.log('Native Apple isolation verification passed.');
  }
}

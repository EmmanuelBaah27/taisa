import { execFileSync } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { parseCatalogRows, validateCatalogCoverage, validateManifest } from './lib.mjs';

function evidenceRootFrom(argv) {
  const index = argv.indexOf('--evidence-root');
  return index === -1 ? 'docs/migration/swiftui' : argv[index + 1];
}

const evidenceRoot = resolve(evidenceRootFrom(process.argv.slice(2)));
const manifest = JSON.parse(await readFile(resolve(evidenceRoot, 'baseline-manifest.json'), 'utf8'));
const errors = validateManifest(manifest);

async function readOptionalJson(path) {
  try {
    return JSON.parse(await readFile(path, 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    throw error;
  }
}

async function readOptionalText(path) {
  try {
    return await readFile(path, 'utf8');
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    throw error;
  }
}

function sourceExistsAtCommit(commit, source) {
  try {
    execFileSync('git', ['cat-file', '-e', `${commit}:${source}`], { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

const catalogPath = resolve(evidenceRoot, 'parity-catalog.md');
const catalogMarkdown = await readOptionalText(catalogPath);
if (manifest.requiredRoutes?.length && catalogMarkdown === null) {
  errors.push('Parity catalog is missing');
}

if (catalogMarkdown !== null) {
  const rows = parseCatalogRows(catalogMarkdown);
  errors.push(...validateCatalogCoverage({ routes: manifest.requiredRoutes ?? [], rows }));
  const allowedStatuses = new Set(['planned', 'captured', 'accepted-difference']);
  const requiredFields = [
    ['Journey', 'journey'],
    ['Source', 'source'],
    ['State', 'state'],
    ['Fixture', 'fixture'],
    ['Expected behavior', 'expectedBehavior'],
    ['Accessibility', 'accessibility'],
    ['API/decision', 'apiDecision'],
    ['Reference', 'reference'],
    ['Native owner', 'nativeOwner'],
    ['Status', 'status'],
  ];
  const mediaManifest = await readOptionalJson(resolve(evidenceRoot, 'reference-media/manifest.json'));
  const mediaPaths = new Set((mediaManifest?.records ?? []).map((record) => record.path));

  for (const row of rows) {
    for (const [label, property] of requiredFields) {
      if (!row[property]) errors.push(`${row.catalogId} missing ${label}`);
    }
    if (row.status && !allowedStatuses.has(row.status)) {
      errors.push(`${row.catalogId} has unknown status: ${row.status}`);
    }
    if (row.source && !sourceExistsAtCommit(manifest.candidate?.commit, row.source)) {
      errors.push(`${row.catalogId} source is absent from candidate: ${row.source}`);
    }
    if (row.reference && !mediaPaths.has(row.reference)) {
      errors.push(`${row.catalogId} reference is absent from media manifest: ${row.reference}`);
    }
  }
}

if (errors.length) {
  process.stderr.write(`${errors.join('\n')}\n`);
  process.exitCode = 1;
} else {
  process.stdout.write('Baseline evidence verification passed.\n');
}

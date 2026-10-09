import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';

const testCommit = execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();

const catalogHeader = '| ID | Journey | Source | State | Fixture | Expected behavior | Accessibility | API/decision | Reference | Native owner | Status |\n|---|---|---|---|---|---|---|---|---|---|---|';

function catalogRow({
  id = 'PC-001',
  source = 'package.json',
  fixture = 'fixture.home.attention',
  accessibility = 'VoiceOver announces the state.',
  reference = 'reference-media/PC-001__iphone__default.png',
} = {}) {
  return `| ${id} | Home | ${source} | default | ${fixture} | Shows the expected state. | ${accessibility} | local-only | ${reference} | Home | planned |`;
}

async function runFixtureVerifier(manifest, files = {}) {
  const root = await mkdtemp(join(tmpdir(), 'taisa-baseline-test-'));
  await writeFile(
    join(root, 'baseline-manifest.json'),
    JSON.stringify({ schemaVersion: 1, candidate: { commit: testCommit }, ...manifest }),
  );
  for (const [path, content] of Object.entries(files)) {
    await mkdir(dirname(join(root, path)), { recursive: true });
    await writeFile(join(root, path), content);
  }
  const result = spawnSync(
    process.execPath,
    ['scripts/swiftui-baseline/verify.mjs', '--evidence-root', root],
    { cwd: process.cwd(), encoding: 'utf8' },
  );
  await rm(root, { recursive: true, force: true });
  return result;
}

test('verification fails while a unique source is unresolved', async () => {
  const result = await runFixtureVerifier({
    sources: [{
      name: 'feature/unique',
      uniqueCommits: ['def456'],
      dirty: [],
      disposition: 'unresolved',
      accountedBy: [],
    }],
  });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /unresolved unique work/);
});

test('verification accepts a source whose unique work is accounted for', async () => {
  const result = await runFixtureVerifier({
    sources: [{
      name: 'feature/accounted',
      uniqueCommits: ['def456'],
      dirty: [],
      disposition: 'accounted',
      accountedBy: ['abc123'],
    }],
  });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Baseline evidence verification passed/);
});

test('catalog verification rejects duplicate IDs', async () => {
  const row = catalogRow();
  const result = await runFixtureVerifier(
    { requiredRoutes: ['package.json'] },
    { 'parity-catalog.md': `${catalogHeader}\n${row}\n${row}\n` },
  );
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Duplicate catalog ID: PC-001/);
});

test('catalog verification rejects an unmapped required route', async () => {
  const result = await runFixtureVerifier(
    { requiredRoutes: ['package.json', 'CLAUDE.md'] },
    { 'parity-catalog.md': `${catalogHeader}\n${catalogRow()}\n` },
  );
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Missing catalog coverage: CLAUDE.md/);
});

test('catalog verification rejects a missing fixture', async () => {
  const result = await runFixtureVerifier(
    { requiredRoutes: ['package.json'] },
    { 'parity-catalog.md': `${catalogHeader}\n${catalogRow({ fixture: '' })}\n` },
  );
  assert.equal(result.status, 1);
  assert.match(result.stderr, /PC-001 missing Fixture/);
});

test('catalog verification rejects a missing accessibility expectation', async () => {
  const result = await runFixtureVerifier(
    { requiredRoutes: ['package.json'] },
    { 'parity-catalog.md': `${catalogHeader}\n${catalogRow({ accessibility: '' })}\n` },
  );
  assert.equal(result.status, 1);
  assert.match(result.stderr, /PC-001 missing Accessibility/);
});

test('catalog verification rejects a reference absent from the media manifest', async () => {
  const result = await runFixtureVerifier(
    { requiredRoutes: ['package.json'] },
    {
      'parity-catalog.md': `${catalogHeader}\n${catalogRow()}\n`,
      'reference-media/manifest.json': JSON.stringify({ schemaVersion: 1, records: [] }),
    },
  );
  assert.equal(result.status, 1);
  assert.match(result.stderr, /PC-001 reference is absent from media manifest/);
});

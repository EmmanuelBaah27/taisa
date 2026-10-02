import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

async function runFixtureVerifier(manifest) {
  const root = await mkdtemp(join(tmpdir(), 'taisa-baseline-test-'));
  await writeFile(
    join(root, 'baseline-manifest.json'),
    JSON.stringify({ schemaVersion: 1, candidate: { commit: 'abc123' }, ...manifest }),
  );
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

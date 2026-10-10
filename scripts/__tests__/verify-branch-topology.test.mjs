import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import test from 'node:test';

const verifier = resolve(import.meta.dirname, '../verify-branch-topology.sh');

function git(cwd, ...args) {
  return execFileSync('git', args, { cwd, encoding: 'utf8' }).trim();
}

async function repository() {
  const cwd = await mkdtemp(join(tmpdir(), 'taisa-topology-'));
  git(cwd, 'init', '-b', 'main');
  git(cwd, 'config', 'user.name', 'Taisa Test');
  git(cwd, 'config', 'user.email', 'taisa-test@example.invalid');
  await writeFile(join(cwd, 'state.txt'), 'main\n');
  git(cwd, 'add', 'state.txt');
  git(cwd, 'commit', '-m', 'main baseline');
  git(cwd, 'branch', 'preview/taisa');
  git(cwd, 'branch', 'feature/work');
  return cwd;
}

function verify(cwd, ...args) {
  return spawnSync('bash', [verifier, ...args], { cwd, encoding: 'utf8' });
}

test('build rejects preview as the work branch', async () => {
  const cwd = await repository();
  const result = verify(cwd, 'build', '--work-ref', 'preview/taisa', '--branch', 'preview/taisa', '--main-ref', 'main', '--preview-ref', 'preview/taisa');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /preview\/taisa.*cannot be a work branch/i);
});

test('build accepts a main-based work branch', async () => {
  const cwd = await repository();
  const result = verify(cwd, 'build', '--work-ref', 'feature/work', '--branch', 'feature/work', '--main-ref', 'main', '--preview-ref', 'preview/taisa');
  assert.equal(result.status, 0, result.stderr);
});

test('build rejects a branch containing preview-only history', async () => {
  const cwd = await repository();
  git(cwd, 'switch', 'preview/taisa');
  await writeFile(join(cwd, 'preview.txt'), 'preview only\n');
  git(cwd, 'add', 'preview.txt');
  git(cwd, 'commit', '-m', 'preview only');
  git(cwd, 'switch', '-c', 'feature/from-preview');
  const result = verify(cwd, 'build', '--work-ref', 'feature/from-preview', '--branch', 'feature/from-preview', '--main-ref', 'main', '--preview-ref', 'preview/taisa');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /contains preview-only history/i);
});

test('ship rejects an unexpected pull request base', async () => {
  const cwd = await repository();
  const result = verify(cwd, 'ship', '--work-ref', 'feature/work', '--branch', 'feature/work', '--pr-base', 'preview/taisa', '--main-ref', 'main', '--preview-ref', 'preview/taisa');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /pull request base must be main/i);
});

test('ship requires the current main revision in the work branch', async () => {
  const cwd = await repository();
  git(cwd, 'switch', 'main');
  await writeFile(join(cwd, 'main-next.txt'), 'new main\n');
  git(cwd, 'add', 'main-next.txt');
  git(cwd, 'commit', '-m', 'advance main');
  const result = verify(cwd, 'ship', '--work-ref', 'feature/work', '--branch', 'feature/work', '--pr-base', 'main', '--main-ref', 'main', '--preview-ref', 'preview/taisa');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /does not contain current main/i);
});

test('ship dry-run rejects a candidate that conflicts with preview', async () => {
  const cwd = await repository();
  git(cwd, 'switch', 'preview/taisa');
  await writeFile(join(cwd, 'state.txt'), 'preview\n');
  git(cwd, 'commit', '-am', 'preview edit');
  git(cwd, 'switch', 'feature/work');
  await writeFile(join(cwd, 'state.txt'), 'work\n');
  git(cwd, 'commit', '-am', 'work edit');
  const result = verify(cwd, 'ship', '--work-ref', 'feature/work', '--branch', 'feature/work', '--pr-base', 'main', '--main-ref', 'main', '--preview-ref', 'preview/taisa');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /conflicts with preview/i);
});

test('preview-sync requires the shipped main revision in preview', async () => {
  const cwd = await repository();
  git(cwd, 'switch', 'main');
  await writeFile(join(cwd, 'shipped.txt'), 'shipped\n');
  git(cwd, 'add', 'shipped.txt');
  git(cwd, 'commit', '-m', 'shipped main');
  const shipped = git(cwd, 'rev-parse', 'main');
  const rejected = verify(cwd, 'preview-sync', '--shipped-ref', shipped, '--main-ref', 'main', '--preview-ref', 'preview/taisa');
  assert.notEqual(rejected.status, 0);
  assert.match(rejected.stderr, /does not contain shipped main/i);
  git(cwd, 'switch', 'preview/taisa');
  git(cwd, 'merge', '--ff-only', 'main');
  const accepted = verify(cwd, 'preview-sync', '--shipped-ref', shipped, '--main-ref', 'main', '--preview-ref', 'preview/taisa');
  assert.equal(accepted.status, 0, accepted.stderr);
});

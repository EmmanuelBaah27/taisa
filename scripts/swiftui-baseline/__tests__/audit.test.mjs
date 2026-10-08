import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

test('legacy audit reports missing branches and continues to later entries', async () => {
  const repository = await mkdtemp(resolve(tmpdir(), 'taisa-audit-test-'));
  const script = resolve('scripts/audit-current-experience.sh');
  try {
    spawnSync('git', ['init', '-b', 'main'], { cwd: repository, encoding: 'utf8' });
    await writeFile(resolve(repository, 'README.md'), 'fixture\n');
    spawnSync('git', ['add', 'README.md'], { cwd: repository, encoding: 'utf8' });
    spawnSync('git', [
      '-c', 'user.name=Taisa Test',
      '-c', 'user.email=taisa-test@example.invalid',
      'commit', '-m', 'fixture',
    ], { cwd: repository, encoding: 'utf8' });

    const result = spawnSync('bash', [script], { cwd: repository, encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /BRANCH feature\/local-first-coaching-platform\nMISSING/);
    assert.match(result.stdout, /BRANCH design-system\nMISSING/);
  } finally {
    await rm(repository, { recursive: true, force: true });
  }
});

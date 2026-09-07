import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const root = new URL('../../../', import.meta.url);

async function source(path) {
  return readFile(new URL(path, root), 'utf8');
}

test('Taisa workflow requires design-system compliance during Build, Review, Preview, and Ship', async () => {
  const workflow = await source('docs/workflow.md');
  for (const stage of ['Build', 'Review', 'Preview', 'Ship']) {
    assert.match(workflow, new RegExp(`${stage}[^\\n]*npm run verify:design-system`, 'i'));
  }
});

test('the orchestrator and workflow verifier enforce the root compliance command', async () => {
  const [orchestrator, verifier] = await Promise.all([
    source('.claude/skills/taisa-workflow/SKILL.md'),
    source('scripts/verify-workflow.sh'),
  ]);
  assert.match(orchestrator, /npm run verify:design-system/);
  assert.match(verifier, /npm run verify:design-system/);
});

test('pull requests cannot pass CI without design-system verification', async () => {
  const ci = await source('.github/workflows/design-system.yml');
  assert.match(ci, /pull_request:/);
  assert.match(ci, /npm run verify:design-system/);
});

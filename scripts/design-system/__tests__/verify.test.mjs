import assert from 'node:assert/strict';
import test from 'node:test';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { verifyPaths } from '../verify.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '__fixtures__');

async function rulesFor(relativePath, options = {}) {
  const findings = await verifyPaths({ root, paths: [relativePath], exceptions: [], ...options });
  return findings.map((finding) => finding.rule);
}

test('semantic Product UI produces no findings', async () => {
  assert.deepEqual(await rulesFor('pass/semantic-screen.tsx'), []);
});

for (const [file, rule] of [
  ['fail/raw-color.tsx', 'no-raw-color'],
  ['fail/raw-text.tsx', 'semantic-text-only'],
  ['fail/legacy-type.tsx', 'no-legacy-type'],
  ['fail/stylesheet.tsx', 'no-stylesheet-create'],
]) {
  test(`${file} reports ${rule}`, async () => {
    assert.ok((await rulesFor(file)).includes(rule));
  });
}

test('expired exact exception is rejected', async () => {
  const exceptions = [{
    file: 'fail/expired-exception.tsx',
    rule: 'no-raw-color',
    reason: 'Fixture proves expiry enforcement',
    owner: 'Taisa Design System',
    expires: '2026-08-24',
    matches: [{ value: '#fff', count: 1 }],
  }];
  assert.ok((await rulesFor('fail/expired-exception.tsx', { exceptions, today: '2026-08-25' })).includes('exception-expired'));
});

test('an exception suppresses only its declared value and count', async () => {
  const exceptions = [{
    file: 'fail/raw-color.tsx',
    rule: 'no-raw-color',
    reason: 'Fixture permits only the first native value',
    owner: 'Taisa Design System',
    expires: '2026-09-25',
    matches: [{ value: '#fff', count: 1 }],
  }];
  assert.ok((await rulesFor('fail/raw-color.tsx', { exceptions, today: '2026-08-25' })).includes('no-raw-color'));
});

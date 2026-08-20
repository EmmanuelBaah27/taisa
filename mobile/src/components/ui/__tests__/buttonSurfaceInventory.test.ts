import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

describe('button surface inventory', () => {
  test('keeps screen-local explicit button styling behind a static gate', () => {
    const packageJson = JSON.parse(readFileSync(resolve(__dirname, '../../../../package.json'), 'utf8'));
    expect(packageJson.scripts['verify:button-surfaces']).toBe('node scripts/verify-button-surfaces.mjs');

    expect(() => execFileSync(
      process.execPath,
      [resolve(__dirname, '../../../../scripts/verify-button-surfaces.mjs')],
      { stdio: 'pipe' },
    )).not.toThrow();
  });
});

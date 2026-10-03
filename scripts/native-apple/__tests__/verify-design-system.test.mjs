import assert from 'node:assert/strict';
import test from 'node:test';

import { rawVisualValues } from '../verify-design-system.mjs';

test('feature views contain no raw color literals', async () => {
  assert.deepEqual(await rawVisualValues('apple/TaisaApp'), []);
});

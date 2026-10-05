import assert from 'node:assert/strict';
import test from 'node:test';

import { isCanonicalTaisaOrigin } from '../../canonical-origin.mjs';

test('accepts canonical GitHub checkout URLs with or without the optional suffix', () => {
  assert.equal(isCanonicalTaisaOrigin('https://github.com/EmmanuelBaah27/taisa.git'), true);
  assert.equal(isCanonicalTaisaOrigin('https://github.com/EmmanuelBaah27/taisa'), true);
  assert.equal(isCanonicalTaisaOrigin('https://github.com/EmmanuelBaah27/taisa/'), true);
  assert.equal(isCanonicalTaisaOrigin('https://github.com/another/repository.git'), false);
});

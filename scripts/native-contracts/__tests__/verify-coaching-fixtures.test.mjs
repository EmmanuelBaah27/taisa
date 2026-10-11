import assert from 'node:assert/strict';
import test from 'node:test';

import {
  INVALID_COACHING_STREAMS,
  VALID_COACHING_STREAMS,
  verifyCoachingFixtures,
} from '../verify-coaching-fixtures.mjs';

test('accepts ordered delta, completed, and failed fixture streams', () => {
  const result = verifyCoachingFixtures({
    valid: VALID_COACHING_STREAMS,
    invalid: [],
  });

  assert.deepEqual(result.validFailures, []);
});

test('rejects wrong request, gaps, conflicting duplicates, unknown fields, and post-terminal data', () => {
  const result = verifyCoachingFixtures({
    valid: [],
    invalid: INVALID_COACHING_STREAMS,
  });

  assert.deepEqual(result.invalidAccepted, []);
});

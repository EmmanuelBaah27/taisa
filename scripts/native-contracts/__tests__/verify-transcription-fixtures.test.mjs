import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import test from 'node:test';

import {
  acceptedInvalidFixtures,
  invalidValidFixtures,
} from '../verify-transcription-fixtures.mjs';

const fixturesRoot = resolve('shared/fixtures/transcription');

test('all valid fixtures satisfy the runtime guard', async () => {
  assert.deepEqual(await invalidValidFixtures(fixturesRoot), []);
});

test('all invalid fixtures are rejected by the runtime guard', async () => {
  assert.deepEqual(await acceptedInvalidFixtures(fixturesRoot), []);
});

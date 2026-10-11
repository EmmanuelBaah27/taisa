import { createRequire } from 'node:module';
import { readdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
require('ts-node').register({
  transpileOnly: true,
  compilerOptions: { module: 'commonjs', moduleResolution: 'node' },
});

const { isCoachingStreamEvent } = require(
  resolve(import.meta.dirname, '../../shared/types/coachingStream.ts'),
);

const fixturesRoot = resolve(import.meta.dirname, '../../shared/fixtures/coaching-stream');

function readStreams(suffix) {
  return readdirSync(fixturesRoot)
    .filter((name) => name.endsWith(suffix))
    .sort()
    .map((name) => ({ name, events: JSON.parse(readFileSync(resolve(fixturesRoot, name), 'utf8')) }));
}

export const VALID_COACHING_STREAMS = readStreams('.valid.json');
export const INVALID_COACHING_STREAMS = readStreams('.invalid.json');

function streamIsValid(stream) {
  if (!Array.isArray(stream.events) || stream.events.length === 0) return false;
  let requestId;
  let terminal = false;
  for (let index = 0; index < stream.events.length; index += 1) {
    const event = stream.events[index];
    if (!isCoachingStreamEvent(event) || terminal || event.sequence !== index) return false;
    requestId ??= event.requestId;
    if (event.requestId !== requestId) return false;
    if (event.type === 'coaching.completed' || event.type === 'coaching.failed') terminal = true;
  }
  return terminal;
}

export function verifyCoachingFixtures({ valid, invalid }) {
  return {
    validFailures: valid.filter((stream) => !streamIsValid(stream)).map((stream) => stream.name),
    invalidAccepted: invalid.filter(streamIsValid).map((stream) => stream.name),
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const result = verifyCoachingFixtures({ valid: VALID_COACHING_STREAMS, invalid: INVALID_COACHING_STREAMS });
  if (result.validFailures.length || result.invalidAccepted.length) {
    console.error(JSON.stringify(result, null, 2));
    process.exitCode = 1;
  } else {
    console.log('Native coaching stream contract fixtures passed.');
  }
}

import { createRequire } from 'node:module';
import { readdir, readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
require('ts-node').register({
  transpileOnly: true,
  compilerOptions: { module: 'commonjs', moduleResolution: 'node' },
});

const { isTranscriptionStreamEvent } = require(
  resolve(import.meta.dirname, '../../shared/types/transcription.ts'),
);

async function fixtureNames(fixturesRoot, suffix) {
  return (await readdir(fixturesRoot))
    .filter((name) => name.endsWith(suffix))
    .sort();
}

async function parseFixture(fixturesRoot, name) {
  return JSON.parse(await readFile(resolve(fixturesRoot, name), 'utf8'));
}

export async function invalidValidFixtures(fixturesRoot) {
  const failures = [];
  for (const name of await fixtureNames(fixturesRoot, '.valid.json')) {
    if (!isTranscriptionStreamEvent(await parseFixture(fixturesRoot, name))) failures.push(name);
  }
  return failures;
}

export async function acceptedInvalidFixtures(fixturesRoot) {
  const failures = [];
  for (const name of await fixtureNames(fixturesRoot, '.invalid.json')) {
    if (isTranscriptionStreamEvent(await parseFixture(fixturesRoot, name))) failures.push(name);
  }
  return failures;
}

async function main() {
  const fixturesRoot = resolve('shared/fixtures/transcription');
  const invalidValid = await invalidValidFixtures(fixturesRoot);
  const acceptedInvalid = await acceptedInvalidFixtures(fixturesRoot);
  if (invalidValid.length || acceptedInvalid.length) {
    console.error(JSON.stringify({ invalidValid, acceptedInvalid }, null, 2));
    process.exitCode = 1;
    return;
  }
  console.log('Native transcription contract fixtures passed.');
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await main();
}

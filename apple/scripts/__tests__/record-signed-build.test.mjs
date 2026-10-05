import assert from 'node:assert/strict';
import test from 'node:test';

import { validateSignedBuild } from '../record-signed-build.mjs';

const validRecord = {
  candidateCommit: 'abc123',
  installedCommit: 'abc123',
  dirty: false,
  xcodeVersion: '26.1.1',
  xcodeBuild: '17B100',
  appBuildNumber: '1',
  bundleIdentifier: 'com.taisa.app.dev',
  environment: 'development',
  contractRevision: 'transcription-fixtures-v1',
  deviceName: 'iPhone 15 Pro',
  deviceIdentifier: 'device-id',
  operatingSystem: 'iOS 26.0',
  installed: true,
  launched: true,
  testerConfirmation: 'Baah confirmed the displayed diagnostics.',
};

test('accepts a complete development signed-build record', () => {
  assert.deepEqual(validateSignedBuild(validRecord), []);
});

test('rejects a record whose installed commit differs from the candidate', () => {
  assert.match(
    validateSignedBuild({ ...validRecord, installedCommit: 'def456' }).join('\n'),
    /installed commit differs/,
  );
});

test('rejects dirty builds and missing launch confirmation', () => {
  const errors = validateSignedBuild({ ...validRecord, dirty: true, launched: false });
  assert.match(errors.join('\n'), /candidate worktree is dirty/);
  assert.match(errors.join('\n'), /launch was not confirmed/);
});

test('rejects a bundle identifier that does not match its environment', () => {
  assert.match(
    validateSignedBuild({
      ...validRecord,
      environment: 'preview',
      bundleIdentifier: 'com.taisa.app.dev',
    }).join('\n'),
    /bundle identifier.*preview environment/,
  );
});

test('requires tester and device evidence', () => {
  const errors = validateSignedBuild({
    ...validRecord,
    deviceName: '',
    operatingSystem: '',
    testerConfirmation: '',
  });
  assert.match(errors.join('\n'), /deviceName is required/);
  assert.match(errors.join('\n'), /operatingSystem is required/);
  assert.match(errors.join('\n'), /testerConfirmation is required/);
});

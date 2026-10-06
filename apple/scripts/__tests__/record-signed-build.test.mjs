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

const personalRecord = {
  ...validRecord,
  environment: 'personal',
  bundleIdentifier: 'com.taisa.app.personal',
  signedEntitlements: { 'application-identifier': 'TEAM.com.taisa.app.personal' },
  provisioningEntitlements: { 'get-task-allow': true },
  backgroundModes: [],
  linkedLibraries: ['/System/Library/Frameworks/Security.framework/Security'],
  linksLiveTransport: false,
};

test('accepts an explicit isolated Personal record without relabeling it development', () => {
  assert.deepEqual(validateSignedBuild(personalRecord), []);
});

test('Personal requires exact identity and explicit capability evidence', () => {
  assert.match(validateSignedBuild({ ...personalRecord, bundleIdentifier: 'com.taisa.app.dev' }).join('\n'), /does not match/);
  for (const field of ['signedEntitlements', 'provisioningEntitlements', 'backgroundModes', 'linkedLibraries', 'linksLiveTransport']) {
    const record = { ...personalRecord };
    delete record[field];
    assert.match(validateSignedBuild(record).join('\n'), new RegExp(field));
  }
});

test('Personal rejects paid capabilities in both signature and profile even with empty values', () => {
  for (const field of ['signedEntitlements', 'provisioningEntitlements']) {
    for (const key of ['com.apple.developer.icloud-container-identifiers', 'com.apple.developer.icloud-services', 'com.apple.developer.ubiquity-kvstore-identifier', 'aps-environment', 'com.apple.developer.associated-domains']) {
      assert.match(validateSignedBuild({ ...personalRecord, [field]: { [key]: [] } }).join('\n'), /forbidden Personal capability/);
    }
  }
});

test('Personal rejects remote notifications and compiled live transport evidence', () => {
  assert.match(validateSignedBuild({ ...personalRecord, backgroundModes: ['remote-notification'] }).join('\n'), /background/);
  assert.match(validateSignedBuild({ ...personalRecord, linksLiveTransport: true }).join('\n'), /linksLiveTransport/);
  for (const library of ['CloudKit.framework/CloudKit', 'TaisaCloudKit', 'CKContainer']) {
    assert.match(validateSignedBuild({ ...personalRecord, linkedLibraries: [library] }).join('\n'), /live transport/);
  }
});

test('Personal rejects malformed isolation evidence', () => {
  for (const [field, value] of [['signedEntitlements', []], ['provisioningEntitlements', null], ['backgroundModes', 'none'], ['linkedLibraries', [null]], ['linksLiveTransport', 'false']]) {
    assert.match(validateSignedBuild({ ...personalRecord, [field]: value }).join('\n'), new RegExp(field));
  }
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

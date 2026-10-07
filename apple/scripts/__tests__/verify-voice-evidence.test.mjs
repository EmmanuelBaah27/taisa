import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import {
  parseVoiceEvidence,
  requiredVoiceCases,
  validateSignedBuildBindings,
  validateVoiceEvidence,
} from '../verify-voice-evidence.mjs';

const commit = '1234567890123456789012345678901234567890';

function validEvidence() {
  return {
    schemaVersion: 1,
    candidateCommit: commit,
    installedCommit: commit,
    dirty: false,
    fixtureRevision: 'voice-session-fixtures-v1',
    backendEnvironment: 'development',
    appVersion: '1.0',
    buildNumber: '1',
    databaseSchemaVersion: '2',
    signer: 'Apple Development',
    provisioningProfile: 'iOS Team Provisioning Profile',
    rows: ['iPhone', 'iPad'].flatMap((deviceFamily) => requiredVoiceCases.map((caseID) => ({
      deviceFamily,
      deviceName: `${deviceFamily} synthetic physical device`,
      deviceIdentifier: `${deviceFamily.toLowerCase()}-registered-id`,
      operatingSystem: 'iOS 26.0',
      physicalDevice: true,
      caseID,
      result: 'pass',
      durationMS: caseID.startsWith('performance.') ? 1_000 : null,
      peakMemoryMB: caseID.startsWith('performance.') ? 128 : null,
    }))),
  };
}

test('accepts complete content-free physical iPhone and iPad evidence', () => {
  assert.deepEqual(validateVoiceEvidence(validEvidence()), []);
});

test('rejects wrong installed commit and fixture revision', () => {
  const evidence = validEvidence();
  evidence.installedCommit = 'abcdefabcdefabcdefabcdefabcdefabcdefabcd';
  evidence.fixtureRevision = 'old-fixtures';
  assert.match(validateVoiceEvidence(evidence).join('\n'), /installed commit|fixture revision/i);
});

test('rejects a candidate commit different from the repository revision', () => {
  assert.match(validateVoiceEvidence(validEvidence(), {
    expectedCommit: 'abcdefabcdefabcdefabcdefabcdefabcdefabcd',
  }).join('\n'), /repository commit/i);
});

test('parses the single machine-readable Markdown evidence block', () => {
  const evidence = validEvidence();
  assert.deepEqual(parseVoiceEvidence(`heading\n<!-- TAISA_VOICE_EVIDENCE\n${JSON.stringify(evidence)}\n-->`), evidence);
  assert.throws(() => parseVoiceEvidence('no evidence'), /block is missing/);
});

test('rejects missing iPhone or iPad evidence', () => {
  const evidence = validEvidence();
  evidence.rows = evidence.rows.filter((row) => row.deviceFamily !== 'iPad');
  assert.match(validateVoiceEvidence(evidence).join('\n'), /iPad/);
});

test('rejects absent interruption, route, connectivity, and cancellation cases', () => {
  const evidence = validEvidence();
  evidence.rows = evidence.rows.filter((row) => ![
    'interruption.phone',
    'route.bluetooth-removal',
    'connectivity.wifi-loss-return',
    'cancellation.coaching',
  ].includes(row.caseID));
  const errors = validateVoiceEvidence(evidence).join('\n');
  assert.match(errors, /interruption\.phone/);
  assert.match(errors, /route\.bluetooth-removal/);
  assert.match(errors, /connectivity\.wifi-loss-return/);
  assert.match(errors, /cancellation\.coaching/);
});

test('rejects simulator-only claims and failed rows', () => {
  const evidence = validEvidence();
  evidence.rows[0].physicalDevice = false;
  evidence.rows[1].result = 'fail';
  const errors = validateVoiceEvidence(evidence).join('\n');
  assert.match(errors, /physical device/i);
  assert.match(errors, /must pass/i);
});

for (const [field, value] of [
  ['transcriptText', 'private words'],
  ['audioPath', '/private/recording.m4a'],
  ['coachingContent', 'private response'],
  ['privateContext', 'private context'],
]) {
  test(`rejects private field ${field}`, () => {
    const evidence = validEvidence();
    evidence.rows[0][field] = value;
    assert.match(validateVoiceEvidence(evidence).join('\n'), /private or unsupported field/i);
  });
}

test('requires bounded numeric performance evidence on both devices', () => {
  const evidence = validEvidence();
  const row = evidence.rows.find((item) => item.caseID === 'performance.streaming');
  row.durationMS = null;
  row.peakMemoryMB = null;
  assert.match(validateVoiceEvidence(evidence).join('\n'), /performance/i);
});

test('rejects voice evidence that is not bound to signed Personal artifacts', () => {
  const evidence = validEvidence();
  const records = ['iphone', 'ipad'].map((family) => JSON.parse(readFileSync(
    new URL(`../../../docs/migration/swiftui/native-build-records/2026-10-06-${family}-personal.json`, import.meta.url),
  )));
  for (const [index, record] of records.entries()) {
    record.appPath = `/nonexistent/retained-personal-${index}/TaisaPersonal.app`;
    record.profilePath = `${record.appPath}/embedded.mobileprovision`;
    record.artifactEvidence.executable = `${record.appPath}/TaisaPersonal`;
  }
  evidence.candidateCommit = records[0].candidateCommit;
  evidence.installedCommit = records[0].installedCommit;
  evidence.appVersion = records[0].appVersion;
  evidence.buildNumber = records[0].appBuildNumber;
  evidence.databaseSchemaVersion = records[0].databaseSchemaVersion;
  evidence.signer = records[0].artifactEvidence.signerCertificateSHA256;
  evidence.provisioningProfile = records[0].artifactEvidence.profileUUID;
  evidence.rows = records.flatMap((record, index) => requiredVoiceCases.map((caseID) => ({
    deviceFamily: index === 0 ? 'iPhone' : 'iPad',
    deviceName: record.deviceName, deviceIdentifier: record.deviceIdentifier,
    operatingSystem: record.operatingSystem, physicalDevice: true, caseID, result: 'pass',
    durationMS: caseID.startsWith('performance.') ? 1_000 : null,
    peakMemoryMB: caseID.startsWith('performance.') ? 128 : null,
  })));
  assert.deepEqual(validateSignedBuildBindings(evidence, records), []);
  records[1].installedCommit = 'abcdefabcdefabcdefabcdefabcdefabcdefabcd';
  assert.match(validateSignedBuildBindings(evidence, records).join('\n'), /commit|installed/i);
});

#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { inspectSignedBuild } from './record-signed-build.mjs';

export const voiceFixtureRevision = 'voice-session-fixtures-v1';

export const requiredVoiceCases = Object.freeze([
  'permission.microphone-allow',
  'permission.microphone-deny',
  'capture.pause-resume',
  'capture.send-boundary',
  'interruption.phone',
  'interruption.siri',
  'interruption.alarm',
  'route.bluetooth-removal',
  'route.wired-removal',
  'lifecycle.background-foreground',
  'lifecycle.lock-unlock',
  'lifecycle.force-quit',
  'connectivity.wifi-loss-return',
  'connectivity.cellular-loss-return',
  'cancellation.capture',
  'cancellation.transcription',
  'cancellation.coaching',
  'conversation.multi-turn',
  'privacy.artifact-scan',
  'accessibility.voiceover',
  'accessibility.dynamic-type',
  'accessibility.reduce-motion',
  'performance.recording',
  'performance.streaming',
]);

const topLevelFields = new Set([
  'schemaVersion', 'candidateCommit', 'installedCommit', 'dirty', 'fixtureRevision',
  'backendEnvironment', 'appVersion', 'buildNumber', 'databaseSchemaVersion',
  'signer', 'provisioningProfile', 'rows',
]);
const rowFields = new Set([
  'deviceFamily', 'deviceName', 'deviceIdentifier', 'operatingSystem', 'physicalDevice',
  'caseID', 'result', 'durationMS', 'peakMemoryMB',
]);
const privateField = /audio|transcript|coaching|content|context|path|recording(?:data|url)|private/i;
const fullCommit = /^[a-f0-9]{40}$/i;
const text = (value) => typeof value === 'string' && value.trim() !== '';

function unsupportedFields(object, allowed, location) {
  if (object === null || typeof object !== 'object' || Array.isArray(object)) return [];
  return Object.keys(object)
    .filter((field) => !allowed.has(field) || privateField.test(field))
    .map((field) => `private or unsupported field at ${location}.${field}`);
}

export function validateVoiceEvidence(evidence = {}, { expectedCommit } = {}) {
  const errors = [];
  const requireFact = (condition, message) => { if (!condition) errors.push(message); };

  requireFact(evidence !== null && typeof evidence === 'object' && !Array.isArray(evidence),
    'evidence must be an object');
  if (evidence === null || typeof evidence !== 'object' || Array.isArray(evidence)) return errors;
  errors.push(...unsupportedFields(evidence, topLevelFields, 'evidence'));

  requireFact(evidence.schemaVersion === 1, 'schemaVersion must be 1');
  requireFact(fullCommit.test(evidence.candidateCommit ?? ''), 'candidate commit must be a full Git commit');
  requireFact(fullCommit.test(evidence.installedCommit ?? ''), 'installed commit must be a full Git commit');
  requireFact(evidence.candidateCommit === evidence.installedCommit,
    'installed commit differs from candidate commit');
  if (expectedCommit !== undefined) {
    requireFact(evidence.candidateCommit === expectedCommit,
      'candidate commit differs from the repository commit being verified');
  }
  requireFact(evidence.dirty === false, 'candidate worktree must be clean');
  requireFact(evidence.fixtureRevision === voiceFixtureRevision,
    `fixture revision must be ${voiceFixtureRevision}`);
  requireFact(['development', 'personal', 'production'].includes(evidence.backendEnvironment),
    'backendEnvironment must name an approved environment');
  requireFact(text(evidence.appVersion), 'appVersion is required');
  requireFact(text(evidence.buildNumber), 'buildNumber is required');
  requireFact(/^[1-9]\d*$/.test(evidence.databaseSchemaVersion ?? ''),
    'databaseSchemaVersion must be a positive integer string');
  requireFact(text(evidence.signer), 'signer is required');
  requireFact(text(evidence.provisioningProfile), 'provisioningProfile is required');
  requireFact(Array.isArray(evidence.rows), 'rows must be an array');

  const rows = Array.isArray(evidence.rows) ? evidence.rows : [];
  const seen = new Set();
  for (const [index, row] of rows.entries()) {
    if (row === null || typeof row !== 'object' || Array.isArray(row)) {
      errors.push(`row ${index} must be an object`);
      continue;
    }
    errors.push(...unsupportedFields(row, rowFields, `rows[${index}]`));
    requireFact(['iPhone', 'iPad'].includes(row.deviceFamily),
      `row ${index} deviceFamily must be iPhone or iPad`);
    requireFact(text(row.deviceName), `row ${index} deviceName is required`);
    requireFact(text(row.deviceIdentifier), `row ${index} deviceIdentifier is required`);
    requireFact(text(row.operatingSystem), `row ${index} operatingSystem is required`);
    requireFact(row.physicalDevice === true, `row ${index} must describe a physical device`);
    requireFact(requiredVoiceCases.includes(row.caseID), `row ${index} has an unsupported caseID`);
    requireFact(row.result === 'pass', `row ${index} must pass`);
    const key = `${row.deviceFamily}:${row.caseID}`;
    requireFact(!seen.has(key), `duplicate evidence row ${key}`);
    seen.add(key);
    if (typeof row.caseID === 'string' && row.caseID.startsWith('performance.')) {
      requireFact(Number.isFinite(row.durationMS) && row.durationMS > 0 && row.durationMS <= 300_000,
        `performance row ${key} requires bounded durationMS`);
      requireFact(Number.isFinite(row.peakMemoryMB) && row.peakMemoryMB > 0 && row.peakMemoryMB <= 2_048,
        `performance row ${key} requires bounded peakMemoryMB`);
    } else {
      requireFact(row.durationMS === null, `non-performance row ${key} durationMS must be null`);
      requireFact(row.peakMemoryMB === null, `non-performance row ${key} peakMemoryMB must be null`);
    }
  }

  for (const family of ['iPhone', 'iPad']) {
    for (const caseID of requiredVoiceCases) {
      requireFact(seen.has(`${family}:${caseID}`), `missing ${family} evidence for ${caseID}`);
    }
  }
  return errors;
}

export function validateSignedBuildBindings(evidence, records = [], inspectionOptions = {}) {
  const errors = [];
  if (!Array.isArray(records) || records.length !== 2) {
    return ['exactly two signed-build records are required'];
  }
  const rows = Array.isArray(evidence?.rows) ? evidence.rows : [];
  const seenDevices = new Set();
  for (const source of records) {
    const inspected = inspectSignedBuild(structuredClone(source), inspectionOptions);
    errors.push(...inspected.errors.map((error) => `signed-build record: ${error}`));
    const record = inspected.record;
    if (record.environment !== 'personal') errors.push('signed-build record must be Personal');
    if (record.artifactEvidence?.signatureVerified !== true) {
      errors.push('signed-build artifact signature was not verified');
    }
    if (record.candidateCommit !== evidence.candidateCommit
        || record.installedCommit !== evidence.installedCommit) {
      errors.push('signed-build commit differs from voice evidence');
    }
    if (record.appVersion !== evidence.appVersion
        || record.appBuildNumber !== evidence.buildNumber
        || record.databaseSchemaVersion !== evidence.databaseSchemaVersion) {
      errors.push('signed-build app metadata differs from voice evidence');
    }
    const deviceRows = rows.filter((row) => row.deviceIdentifier === record.deviceIdentifier);
    if (deviceRows.length === 0) errors.push('signed-build device is absent from voice evidence');
    if (deviceRows.some((row) => row.deviceName !== record.deviceName
        || row.operatingSystem !== record.operatingSystem)) {
      errors.push('signed-build device metadata differs from voice evidence');
    }
    if (seenDevices.has(record.deviceIdentifier)) errors.push('signed-build device records must be distinct');
    seenDevices.add(record.deviceIdentifier);
    if (evidence.provisioningProfile !== record.artifactEvidence?.profileUUID) {
      errors.push('signed-build provisioning profile differs from voice evidence');
    }
    if (evidence.signer !== record.artifactEvidence?.signerCertificateSHA256) {
      errors.push('signed-build signer differs from voice evidence');
    }
  }
  for (const family of ['iPhone', 'iPad']) {
    const identifiers = new Set(rows.filter((row) => row.deviceFamily === family)
      .map((row) => row.deviceIdentifier));
    if (identifiers.size !== 1 || !seenDevices.has([...identifiers][0])) {
      errors.push(`${family} evidence is not bound to one signed-build device record`);
    }
  }
  return errors;
}

export function parseVoiceEvidence(document) {
  const match = document.match(/<!-- TAISA_VOICE_EVIDENCE\s*([\s\S]*?)\s*-->/);
  if (!match) throw new Error('TAISA_VOICE_EVIDENCE block is missing');
  try { return JSON.parse(match[1]); }
  catch (error) { throw new Error(`TAISA_VOICE_EVIDENCE is not valid JSON: ${error.message}`); }
}

async function main() {
  const [inputPath, iphoneRecordPath, ipadRecordPath] = process.argv.slice(2);
  if (!inputPath || !iphoneRecordPath || !ipadRecordPath) {
    throw new Error('usage: verify-voice-evidence.mjs <device-matrix.md> <iphone-signed-build.json> <ipad-signed-build.json>');
  }
  const document = await readFile(inputPath, 'utf8');
  const evidence = parseVoiceEvidence(document);
  const expectedCommit = execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
  const records = await Promise.all([iphoneRecordPath, ipadRecordPath]
    .map(async (recordPath) => JSON.parse(await readFile(recordPath, 'utf8'))));
  const errors = [
    ...validateVoiceEvidence(evidence, { expectedCommit }),
    ...validateSignedBuildBindings(evidence, records),
  ];
  if (errors.length > 0) {
    process.stderr.write(`${errors.map((error) => `- ${error}`).join('\n')}\n`);
    process.exitCode = 1;
    return;
  }
  process.stdout.write(`Voice device evidence verified for ${expectedCommit}.\n`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}

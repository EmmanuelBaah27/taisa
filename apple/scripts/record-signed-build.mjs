#!/usr/bin/env node

import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

const bundleIdentifiers = {
  development: 'com.taisa.app.dev',
  preview: 'com.taisa.app.preview',
  production: 'com.taisa.app',
  personal: 'com.taisa.app.personal',
};

const requiredTextFields = [
  'candidateCommit',
  'installedCommit',
  'xcodeVersion',
  'xcodeBuild',
  'appBuildNumber',
  'bundleIdentifier',
  'environment',
  'contractRevision',
  'deviceName',
  'deviceIdentifier',
  'operatingSystem',
  'testerConfirmation',
];

export function validateSignedBuild(record = {}) {
  const errors = [];

  for (const field of requiredTextFields) {
    if (typeof record[field] !== 'string' || record[field].trim() === '') {
      errors.push(`${field} is required`);
    }
  }

  if (record.candidateCommit && record.installedCommit
      && record.candidateCommit !== record.installedCommit) {
    errors.push('installed commit differs from candidate commit');
  }
  if (record.dirty !== false) errors.push('candidate worktree is dirty');
  if (record.installed !== true) errors.push('installation was not confirmed');
  if (record.launched !== true) errors.push('launch was not confirmed');

  const expectedBundleIdentifier = bundleIdentifiers[record.environment];
  if (!expectedBundleIdentifier) {
    errors.push(`unsupported environment: ${record.environment ?? '<missing>'}`);
  } else if (record.bundleIdentifier !== expectedBundleIdentifier) {
    errors.push(
      `bundle identifier ${record.bundleIdentifier ?? '<missing>'} does not match `
      + `${record.environment} environment (${expectedBundleIdentifier})`,
    );
  }

  if (record.environment === 'personal') {
    // These are observed build/profile facts, not inferred from the lane name.
    for (const field of ['signedEntitlements', 'provisioningEntitlements']) {
      const rights = record[field];
      if (!rights || typeof rights !== 'object' || Array.isArray(rights)) {
        errors.push(`${field} must contain inspected Personal entitlement evidence`);
      } else {
        for (const key of Object.keys(rights)) {
          if (/icloud|cloudkit|ubiquity|aps-environment|push|associated-domains/i.test(key)) {
            errors.push(`forbidden Personal capability in ${field}: ${key}`);
          }
        }
      }
    }
    for (const field of ['backgroundModes', 'linkedLibraries']) {
      if (!Array.isArray(record[field]) || record[field].some((item) => typeof item !== 'string')) {
        errors.push(`${field} must contain inspected Personal build evidence`);
      }
    }
    if (Array.isArray(record.backgroundModes) && record.backgroundModes.length > 0) {
      errors.push('Personal background modes must be empty');
    }
    if (Array.isArray(record.linkedLibraries)
        && record.linkedLibraries.some((name) => /CloudKit|CKContainer/i.test(name))) {
      errors.push('Personal build contains live transport linkage');
    }
    if (record.linksLiveTransport !== false) {
      errors.push('Personal linksLiveTransport must be explicitly false after binary inspection');
    }
  }

  return errors;
}

async function main() {
  const inputPath = process.argv[2];
  if (!inputPath) {
    throw new Error('usage: record-signed-build.mjs <record.json>');
  }

  const record = JSON.parse(await readFile(inputPath, 'utf8'));
  const errors = validateSignedBuild(record);
  if (errors.length > 0) {
    process.stderr.write(`${errors.map((error) => `- ${error}`).join('\n')}\n`);
    process.exitCode = 1;
    return;
  }

  process.stdout.write(`${JSON.stringify(record, null, 2)}\n`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}

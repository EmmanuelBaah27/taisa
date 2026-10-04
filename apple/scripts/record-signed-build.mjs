#!/usr/bin/env node

import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

const bundleIdentifiers = {
  development: 'com.taisa.app.dev',
  preview: 'com.taisa.app.preview',
  production: 'com.taisa.app',
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

#!/usr/bin/env node

import { existsSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { inspectPersonalBuild, validateRetainedPersonalEvidence } from './inspect-personal-build.mjs';

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

export function inspectSignedBuild(record = {}, options = {}) {
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
    if (typeof record.appVersion !== 'string' || !/^\d+\.\d+(?:\.\d+)?$/.test(record.appVersion)) {
      errors.push('Personal appVersion must be a dotted numeric marketing version');
    }
    if (typeof record.databaseSchemaVersion !== 'string'
        || !/^[1-9]\d*$/.test(record.databaseSchemaVersion)) {
      errors.push('Personal databaseSchemaVersion must be a positive integer string');
    }
    if (typeof record.parityCatalogRevision !== 'string'
        || !/^[a-f0-9]{40}$/i.test(record.parityCatalogRevision)) {
      errors.push('Personal parityCatalogRevision must be a full Git commit');
    }
    try {
      const appExists = typeof record.appPath === 'string' && existsSync(record.appPath);
      const profileExists = typeof record.profilePath === 'string' && existsSync(record.profilePath);
      const inspected = options.preferRetainedEvidence || (!appExists && !profileExists)
        ? validateRetainedPersonalEvidence(record)
        : inspectPersonalBuild(record, options);
      errors.push(...inspected.errors);
      record = { ...record, ...inspected.evidence };
    } catch (error) { errors.push(`Personal artifact inspection failed: ${error.message}`); }
  }

  return { errors, record };
}

export function validateSignedBuild(record = {}, options = {}) {
  return inspectSignedBuild(record, options).errors;
}

async function main() {
  const inputPath = process.argv[2];
  if (!inputPath) {
    throw new Error('usage: record-signed-build.mjs <record.json>');
  }

  const record = JSON.parse(await readFile(inputPath, 'utf8'));
  const inspected = inspectSignedBuild(record);
  const { errors } = inspected;
  if (errors.length > 0) {
    process.stderr.write(`${errors.map((error) => `- ${error}`).join('\n')}\n`);
    process.exitCode = 1;
    return;
  }

  process.stdout.write(`${JSON.stringify(inspected.record, null, 2)}\n`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}

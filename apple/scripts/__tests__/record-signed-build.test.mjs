import assert from 'node:assert/strict';
import test from 'node:test';
import { spawnSync } from 'node:child_process';
import { X509Certificate } from 'node:crypto';
import { rootCertificates } from 'node:tls';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { inspectSignedBuild, validateSignedBuild } from '../record-signed-build.mjs';

// Public CA certificates provide real, parseable DER without generating keys,
// signing apps, reading a keychain, or contacting a certificate issuer.
const signerCertificate = new X509Certificate(rootCertificates[0]);
const unrelatedCertificate = new X509Certificate(rootCertificates[1]);

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
  candidateCommit: '1234567890123456789012345678901234567890',
  installedCommit: '1234567890123456789012345678901234567890',
  teamIdentifier: 'XH59HG6MSY',
};

function fixture(t) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'taisa-signed-artifact-test-')));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const appPath = join(root, 'TaisaPersonal.app');
  mkdirSync(appPath);
  const profilePath = join(appPath, 'embedded.mobileprovision');
  writeFileSync(profilePath, 'SIGNED_CMS_FIXTURE');
  writeFileSync(join(appPath, 'Info.plist'), 'INFO_FIXTURE');
  const executable = join(appPath, 'TaisaPersonal');
  const image = Buffer.concat([Buffer.from([0xcf, 0xfa, 0xed, 0xfe]), Buffer.from(personalRecord.candidateCommit + ' transcription-fixtures-v1')]);
  writeFileSync(executable, image);
  const facts = {
    signerCertificate: signerCertificate.raw,
    info: { CFBundleIdentifier: 'com.taisa.app.personal', TaisaEnvironment: 'personal', CFBundleExecutable: 'TaisaPersonal', CFBundleVersion: '1' },
    rights: { 'application-identifier': 'XH59HG6MSY.com.taisa.app.personal', 'com.apple.developer.team-identifier': 'XH59HG6MSY', 'get-task-allow': true },
    profile: { UUID: '11111111-1111-4111-8111-111111111111', TeamIdentifier: ['XH59HG6MSY'], ApplicationIdentifierPrefix: ['XH59HG6MSY'], ExpirationDate: '2099-01-01T00:00:00Z', ProvisionedDevices: ['device-id'], Entitlements: { 'application-identifier': 'XH59HG6MSY.com.taisa.app.personal', 'com.apple.developer.team-identifier': 'XH59HG6MSY', 'get-task-allow': true } },
    signature: 'Identifier=com.taisa.app.personal\nAuthority=Apple Development: Synthetic Test\nTeamIdentifier=XH59HG6MSY\n',
    links: `${executable}:\n\t/System/Library/Frameworks/Security.framework/Security (compatibility version 1.0.0, current version 1.0.0)\n`,
    symbols: '0000000000001000 T _main\n',
  };
  facts.profile.DeveloperCertificates = [signerCertificate.raw.toString('base64')];
  const calls = [];
  const run = (command, args, options = {}) => {
    calls.push([command, args]);
    if (command === 'codesign') {
      if (args.includes('--extract-certificates')) {
        if (facts.signerCertificate !== undefined) writeFileSync(args[args.indexOf('--extract-certificates') + 1] + '0', facts.signerCertificate);
        return { stdout: '', stderr: '' };
      }
      if (args.includes('--verify')) { if (facts.unsigned) throw new Error('unsigned'); return { stdout: '', stderr: '' }; }
      if (args.includes('--entitlements')) return { stdout: 'RIGHTS_FIXTURE', stderr: '' };
      return { stdout: '', stderr: facts.signature };
    }
    if (command === 'security') return { stdout: 'PROFILE_FIXTURE', stderr: '' };
    if (command === 'plutil') {
      if (args[0] === '-insert') return { stdout: 'WRAPPED_PROFILE_FIXTURE', stderr: '' };
      if (args[0] === '-extract') {
        if (args[1] === 'Profile') return { stdout: Object.keys(facts.profile).join('\n'), stderr: '' };
        const path = args[1].replace('Profile.', '').split('.');
        const value = path.reduce((object, key) => object?.[key], facts.profile);
        if (value === undefined) throw new Error('missing profile field');
        if (args.includes('array')) {
          if (!Array.isArray(value)) throw new Error('wrong profile field type');
          return { stdout: `${value.length}\n`, stderr: '' };
        }
        return { stdout: args[2] === 'raw' ? value + '\n' : JSON.stringify(value), stderr: '' };
      }
      return { stdout: JSON.stringify(options.input === 'RIGHTS_FIXTURE' ? facts.rights : options.input === 'PROFILE_FIXTURE' ? facts.profile : facts.info), stderr: '' };
    }
    if (command === 'otool') return { stdout: facts.links, stderr: '' };
    if (command === 'nm') return { stdout: facts.symbols, stderr: '' };
    throw new Error('Unexpected command');
  };
  return { root, appPath, profilePath, executable, image, facts, calls, record: { ...personalRecord, appPath, profilePath }, options: { run, now: new Date('2026-10-06T00:00:00Z') } };
}

test('Personal rejects empty self-reported evidence without real artifacts', () => {
  assert.match(validateSignedBuild({ ...personalRecord, signedEntitlements: {}, provisioningEntitlements: {}, backgroundModes: [], linkedLibraries: [], linksLiveTransport: false }).join('\n'), /appPath|artifact/);
});

test('Personal rejects caller evidence contradicting inspected facts', t => {
  const f = fixture(t);
  for (const [field, value] of Object.entries({ signedEntitlements: {}, provisioningEntitlements: {},
    backgroundModes: ['remote-notification'], linkedLibraries: [], linksLiveTransport: true })) {
    assert.match(validateSignedBuild({ ...f.record, [field]: value }, f.options).join('\n'),
      new RegExp(`caller ${field} disagrees`));
  }
});

test('Personal records the matched actual signer certificate even when it is not first in the profile', t => {
  const f = fixture(t);
  f.facts.profile.DeveloperCertificates.unshift(unrelatedCertificate.raw.toString('base64'));
  const result = inspectSignedBuild(f.record, f.options);
  assert.deepEqual(result.errors, []);
  assert.equal(result.record.artifactEvidence.signerCertificateSHA256,
    signerCertificate.fingerprint256.replaceAll(':', '').toLowerCase());
});

for (const [name, certificates] of [
  ['missing', undefined], ['empty', []], ['not an array', {}],
  ['unrelated same-team signer', [unrelatedCertificate.raw.toString('base64')]],
  ['invalid base64', ['%%%not-base64%%%']],
  ['malformed DER', [Buffer.from('UNRELATED_SIGNER_CERTIFICATE').toString('base64')]],
  ['malformed entry after matching signer', [signerCertificate.raw.toString('base64'), 'AAAA']],
]) {
  test(`Personal rejects ${name} profile developer certificates`, t => {
    const f = fixture(t);
    f.facts.profile.DeveloperCertificates = certificates;
    assert.notDeepEqual(validateSignedBuild(f.record, f.options), []);
  });
}

for (const [name, certificate] of [['missing', undefined], ['empty', Buffer.alloc(0)], ['malformed', Buffer.from('NOT_A_CERTIFICATE')]]) {
  test(`Personal rejects ${name} extracted app signer certificate`, t => {
    const f = fixture(t);
    f.facts.signerCertificate = certificate;
    assert.notDeepEqual(validateSignedBuild(f.record, f.options), []);
  });
}

test('Personal accepts inspected signed app and profile and invokes signature verification', t => {
  const f = fixture(t);
  assert.deepEqual(validateSignedBuild(f.record, f.options), []);
  assert(f.calls.some(([command, args]) => command === 'codesign' && args.includes('--verify')));
  assert(f.calls.some(([command, args]) => command === 'security' && args.includes(f.profilePath)));
  assert(f.calls.some(([command, args]) => command === 'otool' && args.includes(f.executable)));
});

test('Personal handles real profile plist date and certificate types using local plutil', { skip: process.platform !== 'darwin' }, t => {
  const f = fixture(t);
  const xml = value => {
    if (Array.isArray(value)) return `<array>${value.map(xml).join('')}</array>`;
    if (typeof value === 'boolean') return value ? '<true/>' : '<false/>';
    if (typeof value === 'object') return `<dict>${Object.entries(value).map(([key, item]) => `<key>${key}</key>${key === 'DeveloperCertificates' ? `<array>${item.map(data => `<data>${data}</data>`).join('')}</array>` : xml(item)}`).join('')}</dict>`;
    return `<string>${value}</string>`;
  };
  const profileXML = `<?xml version="1.0"?><plist version="1.0">${xml(f.facts.profile)
    .replace('<string>2099-01-01T00:00:00Z</string>', '<date>2099-01-01T00:00:00Z</date>')
    .replace('<dict>', '<dict><key>CreationDate</key><date>2026-10-06T00:00:00Z</date>')}</plist>`;
  const run = (command, args, options = {}) => {
    if (command === 'security') return { stdout: profileXML, stderr: '' };
    if (command === 'plutil' && (args[0] === '-insert' || args[0] === '-extract')) {
      const result = spawnSync('plutil', args, { encoding: 'utf8', input: options.input });
      if (result.status !== 0) throw new Error('plutil failed');
      return result;
    }
    return f.options.run(command, args, options);
  };
  const result = inspectSignedBuild(f.record, { ...f.options, run });
  assert.deepEqual(result.errors, []);
  assert.equal(result.record.artifactEvidence.teamIdentifier, 'XH59HG6MSY');
  assert.equal(result.record.artifactEvidence.images.length, 1);
  assert.match(result.record.artifactEvidence.profileSHA256, /^[a-f0-9]{64}$/);
  assert.deepEqual(result.record.signedEntitlements, f.facts.rights);
});

test('Personal rejects missing empty unsigned and unreadable inspection evidence', t => {
  const f = fixture(t);
  for (const field of ['appPath', 'profilePath']) {
    assert.match(validateSignedBuild({ ...f.record, [field]: '' }, f.options).join('\n'), new RegExp(field));
  }
  f.facts.unsigned = true;
  assert.match(validateSignedBuild(f.record, f.options).join('\n'), /inspection|signature/);
  f.facts.unsigned = false;
  assert.match(validateSignedBuild(f.record, { ...f.options, run: () => ({ stdout: '', stderr: '' }) }).join('\n'), /inspection|empty/);
  rmSync(f.profilePath);
  assert.match(validateSignedBuild(f.record, f.options).join('\n'), /profile|artifact/);
  writeFileSync(f.profilePath, '');
  assert.match(validateSignedBuild(f.record, f.options).join('\n'), /empty|artifact/);
});

test('Personal rejects profile paths not embedded in the inspected app', t => {
  const f = fixture(t);
  const other = join(f.root, 'other.mobileprovision');
  writeFileSync(other, 'OTHER_PROFILE');
  assert.match(validateSignedBuild({ ...f.record, profilePath: other }, f.options).join('\n'), /embedded/);
});

test('Personal rejects contradictory and missing signed or profile identities', t => {
  const f = fixture(t);
  f.facts.rights['application-identifier'] = 'OTHERTEAM.com.taisa.app';
  f.facts.profile.Entitlements['application-identifier'] = 'DIFFERENTTEAM.com.other.app';
  assert.match(validateSignedBuild(f.record, f.options).join('\n'), /application.*identifier/);
  for (const key of ['application-identifier', 'com.apple.developer.team-identifier']) {
    const clean = fixture(t);
    delete clean.facts.rights[key];
    assert.match(validateSignedBuild(clean.record, clean.options).join('\n'), /identity|identifier/);
    const profile = fixture(t);
    delete profile.facts.profile.Entitlements[key];
    assert.match(validateSignedBuild(profile.record, profile.options).join('\n'), /identity|identifier/);
  }
});

test('Personal rejects wrong approved team signature team prefix bundle and app build', t => {
  for (const mutate of [
    f => { f.record.teamIdentifier = 'OTHERTEAM1'; },
    f => { delete f.record.teamIdentifier; },
    f => { f.facts.signature = 'Identifier=com.taisa.app.personal\nTeamIdentifier=OTHERTEAM1\n'; },
    f => { f.facts.profile.TeamIdentifier = ['OTHERTEAM1']; },
    f => { f.facts.profile.ApplicationIdentifierPrefix = ['OTHERTEAM1']; },
    f => { f.facts.info.CFBundleIdentifier = 'com.taisa.app'; },
    f => { f.facts.info.TaisaEnvironment = 'development'; },
    f => { f.facts.info.CFBundleVersion = '2'; },
    f => { f.facts.profile.Entitlements['application-identifier'] = 'XH59HG6MSY.*'; },
  ]) {
    const f = fixture(t); mutate(f);
    assert.notDeepEqual(validateSignedBuild(f.record, f.options), []);
  }
});

test('Personal rejects expired malformed undated or device-ineligible profiles', t => {
  for (const mutate of [
    f => { f.facts.profile.ExpirationDate = '2020-01-01T00:00:00Z'; },
    f => { f.facts.profile.ExpirationDate = 'invalid'; },
    f => { delete f.facts.profile.ExpirationDate; },
    f => { f.facts.profile.ProvisionedDevices = ['other-device']; },
    f => { delete f.facts.profile.ProvisionedDevices; },
    f => { f.facts.profile.ProvisionsAllDevices = true; },
    f => { f.facts.profile = {}; },
  ]) {
    const f = fixture(t); mutate(f);
    assert.notDeepEqual(validateSignedBuild(f.record, f.options), []);
  }
});

test('Personal rejects actual forbidden capabilities background modes and linkage despite clean caller claims', t => {
  for (const field of ['rights', 'profile']) {
    for (const key of ['com.apple.developer.icloud-services', 'com.apple.developer.ubiquity-kvstore-identifier', 'aps-environment', 'com.apple.developer.associated-domains']) {
      const f = fixture(t);
      (field === 'rights' ? f.facts.rights : f.facts.profile.Entitlements)[key] = [];
      assert.match(validateSignedBuild({ ...f.record, signedEntitlements: {}, provisioningEntitlements: {}, linksLiveTransport: false }, f.options).join('\n'), /forbidden Personal capability/);
    }
  }
  const background = fixture(t); background.facts.info.UIBackgroundModes = ['remote-notification'];
  assert.match(validateSignedBuild(background.record, background.options).join('\n'), /background/);
  const linked = fixture(t); linked.facts.links += '\t/System/Library/Frameworks/CloudKit.framework/CloudKit (compatibility version 1.0.0)\n';
  assert.match(validateSignedBuild(linked.record, linked.options).join('\n'), /live transport/);
});

test('Personal scans embedded Mach-O images and rejects missing linkage and different candidate bytes', t => {
  const f = fixture(t);
  mkdirSync(join(f.appPath, 'Frameworks'));
  const library = join(f.appPath, 'Frameworks', 'Extra.dylib');
  writeFileSync(library, Buffer.concat([f.image, Buffer.from('CKContainer')]));
  assert.match(validateSignedBuild(f.record, f.options).join('\n'), /live transport/);
  rmSync(library);
  f.facts.links = '';
  assert.match(validateSignedBuild(f.record, f.options).join('\n'), /linkage|empty/);
  f.facts.links = `${f.executable}:\n\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0)\n`;
  writeFileSync(f.executable, Buffer.from([0xcf, 0xfa, 0xed, 0xfe]));
  assert.match(validateSignedBuild(f.record, f.options).join('\n'), /candidate/);
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

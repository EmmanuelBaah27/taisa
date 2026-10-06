import { createHash, X509Certificate } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { lstatSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, join, resolve } from 'node:path';
import { isDeepStrictEqual } from 'node:util';

const bundle = 'com.taisa.app.personal';
const forbidden = /icloud|cloudkit|ubiquity|aps-environment|push|associated-domains/i;
const liveTransport = /TaisaCloudKit|CKContainer|CloudKit\.framework/;
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const hash = value => typeof value === 'string' && /^[a-f0-9]{64}$/i.test(value);
const textArray = value => Array.isArray(value) && value.length > 0
  && value.every(item => typeof item === 'string' && item.trim() !== '');

function evidenceWithoutInspectionTime(value) {
  if (!object(value)) return value;
  const copy = structuredClone(value);
  delete copy.inspectedAt;
  return copy;
}

export function validateRetainedPersonalEvidence(record) {
  const errors = [];
  const requireFact = (condition, message) => { if (!condition) errors.push(message); };
  const team = record.teamIdentifier;
  const appIdentifier = `${team}.${bundle}`;
  requireFact(typeof record.appPath === 'string' && resolve(record.appPath).endsWith('.app'),
    'retained Personal appPath must identify an app bundle');
  requireFact(typeof record.profilePath === 'string'
    && resolve(record.profilePath) === join(resolve(record.appPath ?? ''), 'embedded.mobileprovision'),
  'retained Personal profilePath must identify the embedded profile');
  requireFact(typeof team === 'string' && /^[A-Z0-9]{10}$/.test(team),
    'retained Personal teamIdentifier is invalid');
  for (const [name, rights] of Object.entries({
    signedEntitlements: record.signedEntitlements,
    provisioningEntitlements: record.provisioningEntitlements,
  })) {
    requireFact(object(rights), `retained ${name} dictionary is required`);
    requireFact(rights?.['application-identifier'] === appIdentifier,
      `retained ${name} application-identifier mismatch or missing`);
    requireFact(rights?.['com.apple.developer.team-identifier'] === team,
      `retained ${name} team-identifier mismatch or missing`);
    requireFact(rights?.['get-task-allow'] === true,
      `retained ${name} must authorize development debugging`);
    for (const key of Object.keys(object(rights) ? rights : {})) {
      if (forbidden.test(key)) errors.push(`forbidden Personal capability in retained ${name}: ${key}`);
    }
  }
  requireFact(Array.isArray(record.backgroundModes) && record.backgroundModes.length === 0,
    'retained Personal background modes must be empty');
  requireFact(textArray(record.linkedLibraries), 'retained Personal linkedLibraries are required');
  requireFact(record.linksLiveTransport === false,
    'retained Personal linksLiveTransport must be false');

  const artifact = record.artifactEvidence;
  requireFact(object(artifact), 'retained Personal artifactEvidence is required');
  if (object(artifact)) {
    requireFact(artifact.attestationType === 'live-artifact-inspection',
      'retained artifact attestationType is invalid');
    requireFact(artifact.signatureVerified === true,
      'retained artifact signature verification is required');
    requireFact(artifact.teamIdentifier === team, 'retained artifact team identifier mismatch');
    requireFact(typeof artifact.executable === 'string'
      && resolve(artifact.executable).startsWith(`${resolve(record.appPath ?? '')}/`),
    'retained artifact executable path is invalid');
    requireFact(typeof artifact.profileUUID === 'string'
      && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(artifact.profileUUID),
    'retained artifact profile UUID is invalid');
    requireFact(typeof artifact.profileExpiration === 'string'
      && Number.isFinite(Date.parse(artifact.profileExpiration)),
    'retained artifact profile expiration is invalid');
    requireFact(hash(artifact.signerCertificateSHA256),
      'retained artifact signer certificate hash is invalid');
    requireFact(hash(artifact.profileSHA256), 'retained artifact profile hash is invalid');
    requireFact(hash(artifact.infoPlistSHA256), 'retained artifact Info.plist hash is invalid');
    requireFact(typeof artifact.inspectedAt === 'string' && Number.isFinite(Date.parse(artifact.inspectedAt)),
      'retained artifact inspection timestamp is invalid');
    requireFact(Array.isArray(artifact.images) && artifact.images.length > 0,
      'retained artifact image evidence is required');
    const paths = new Set(), libraries = new Set();
    for (const image of Array.isArray(artifact.images) ? artifact.images : []) {
      const safePath = object(image) && typeof image.path === 'string' && image.path !== ''
        && !image.path.startsWith('/') && !image.path.split('/').includes('..');
      requireFact(safePath && !paths.has(image.path), 'retained artifact image path is invalid or duplicated');
      if (safePath) paths.add(image.path);
      requireFact(hash(image?.sha256), 'retained artifact image hash is invalid');
      requireFact(textArray(image?.linkedLibraries),
        'retained artifact image linked libraries are required');
      for (const library of Array.isArray(image?.linkedLibraries) ? image.linkedLibraries : []) {
        libraries.add(library);
      }
    }
    requireFact(isDeepStrictEqual([...libraries].sort(), record.linkedLibraries),
      'retained linkedLibraries disagree with artifact image evidence');
  }
  return { errors, evidence: {
    evidenceValidation: {
      mode: 'retained-attestation-only',
      liveReinspectionPerformed: false,
      statement: 'Validated retained inspection evidence only; the signed artifact was unavailable for live reinspection.',
    },
  } };
}

function runCommand(command, args, options = {}) {
  const result = spawnSync(command, args, { encoding: 'utf8', input: options.input,
    maxBuffer: 32 * 1024 * 1024, timeout: 30_000 });
  if (result.error || result.status !== 0) throw new Error(`${command} inspection failed`);
  return { stdout: result.stdout, stderr: result.stderr };
}

function regularFile(path) {
  if (!lstatSync(path).isFile()) throw new Error('artifact must be a regular file');
  const bytes = readFileSync(path);
  if (!bytes.length) throw new Error('empty artifact');
  return bytes;
}

function bundleFiles(path) {
  return readdirSync(path).sort().flatMap(name => {
    const file = join(path, name), stat = lstatSync(file);
    if (stat.isSymbolicLink()) throw new Error('artifact contains a symbolic link');
    if (stat.isDirectory()) return bundleFiles(file);
    if (!stat.isFile()) throw new Error('artifact contains an unsupported file');
    return [file];
  });
}

function isMachO(bytes) {
  return bytes.length >= 4 && [0xfeedface, 0xcefaedfe, 0xfeedfacf, 0xcffaedfe,
    0xcafebabe, 0xbebafeca, 0xcafebabf, 0xbfbafeca].includes(bytes.readUInt32BE(0));
}

function certificateSHA256(bytes) {
  try {
    const certificate = new X509Certificate(bytes);
    // Require exactly one DER certificate, not a PEM wrapper or trailing data.
    if (!certificate.raw.equals(bytes)) throw new Error('noncanonical DER');
    return sha256(certificate.raw);
  } catch { throw new Error('malformed signing certificate DER'); }
}

function inspectSignerCertificate(command, appPath) {
  const directory = mkdtempSync(join(tmpdir(), 'taisa-signer-certificate-'));
  try {
    const prefix = join(directory, 'signer-');
    // Display/extract only: codesign writes public DER files into our private
    // temporary directory, never changes the app or accesses a signing key.
    command('codesign', ['-d', `--extract-certificates=${prefix}`, appPath]);
    return certificateSHA256(regularFile(`${prefix}0`));
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

/** The command runner is injectable only by module callers/tests, never record JSON.
 * All paths, bytes, image enumeration and hashes always come from the filesystem.
 * No signing, provisioning, network or device operation is performed here. */
export function inspectPersonalBuild(record, { run = runCommand, now = new Date() } = {}) {
  for (const field of ['appPath', 'profilePath']) {
    if (typeof record[field] !== 'string' || !record[field].trim()) throw new Error(`${field} is required`);
  }
  const suppliedAppPath = resolve(record.appPath);
  if (!suppliedAppPath.endsWith('.app') || !lstatSync(suppliedAppPath).isDirectory()) throw new Error('appPath must be a non-symlink app directory');
  // macOS /var and /tmp aliases are legitimate ancestors; the artifacts themselves cannot be links.
  const appPath = realpathSync(suppliedAppPath);
  const profileBytes = regularFile(resolve(record.profilePath));
  const profilePath = realpathSync(record.profilePath);
  if (profilePath !== join(appPath, 'embedded.mobileprovision')) throw new Error('profilePath must be the app embedded.mobileprovision');
  const infoPath = join(appPath, 'Info.plist');
  const infoBytes = regularFile(infoPath);
  const command = (name, args, input) => {
    try { return run(name, args, input === undefined ? {} : { input }); }
    catch { throw new Error(`${name} inspection failed`); }
  };
  const parsePlist = (args, input) => {
    const output = command('plutil', args, input).stdout;
    if (typeof output !== 'string' || !output.trim()) throw new Error('empty plist inspection');
    const value = JSON.parse(output);
    if (!object(value) || !Object.keys(value).length) throw new Error('empty plist inspection');
    return value;
  };
  const convert = input => {
    if (typeof input !== 'string' || !input.trim()) throw new Error('empty entitlement/profile inspection');
    return parsePlist(['-convert', 'json', '-o', '-', '-'], input);
  };
  const info = parsePlist(['-convert', 'json', '-o', '-', infoPath]);
  if (typeof info.CFBundleExecutable !== 'string' || !info.CFBundleExecutable
      || basename(info.CFBundleExecutable) !== info.CFBundleExecutable
      || ['.', '..'].includes(info.CFBundleExecutable)) throw new Error('invalid artifact executable');
  const executable = join(appPath, info.CFBundleExecutable);
  const executableBytes = regularFile(executable);
  if (!isMachO(executableBytes)) throw new Error('artifact executable is not Mach-O');

  command('codesign', ['--verify', '--deep', '--strict', appPath]);
  const signatureOutput = command('codesign', ['-d', '--verbose=4', appPath]);
  const signature = `${signatureOutput.stdout}\n${signatureOutput.stderr}`;
  const signerCertificateSHA256 = inspectSignerCertificate(command, appPath);
  const signedEntitlements = convert(command('codesign', ['-d', '--entitlements', ':-', appPath]).stdout);
  const profileXML = command('security', ['cms', '-D', '-i', profilePath]).stdout;
  if (typeof profileXML !== 'string' || !profileXML.trim()) throw new Error('empty profile inspection');
  // Whole-profile JSON conversion fails on real plist dates and certificate data.
  // Extract required facts individually without dropping explicit-device checks.
  const profile = {};
  const wrappedProfile = command('plutil', ['-insert', 'Profile', '-xml', profileXML, '-o', '-', '-'],
    '<?xml version="1.0"?><plist version="1.0"><dict/></plist>').stdout;
  if (typeof wrappedProfile !== 'string' || !wrappedProfile.trim()) throw new Error('empty profile inspection');
  const profileKeys = command('plutil', ['-extract', 'Profile', 'raw', '-expect', 'dictionary', '-o', '-', '-'], wrappedProfile).stdout;
  if (typeof profileKeys !== 'string' || !profileKeys.trim()) throw new Error('empty profile inspection');
  const keys = ['TeamIdentifier', 'ApplicationIdentifierPrefix', 'ProvisionedDevices', 'Entitlements'];
  if (profileKeys.split('\n').includes('ProvisionsAllDevices')) keys.push('ProvisionsAllDevices');
  for (const key of keys) {
    const output = command('plutil', ['-extract', `Profile.${key}`, key === 'ProvisionsAllDevices' ? 'raw' : 'json', '-o', '-', '-'], wrappedProfile).stdout;
    if (typeof output !== 'string' || !output.trim()) throw new Error('empty profile inspection');
    profile[key] = JSON.parse(output);
  }
  profile.UUID = command('plutil', ['-extract', 'Profile.UUID', 'raw', '-expect', 'string', '-o', '-', '-'], wrappedProfile).stdout?.trim();
  profile.ExpirationDate = command('plutil', ['-extract', 'Profile.ExpirationDate', 'raw', '-expect', 'date', '-o', '-', '-'], wrappedProfile).stdout?.trim();
  const certificateCount = command('plutil', ['-extract', 'Profile.DeveloperCertificates', 'raw', '-expect', 'array', '-o', '-', '-'], wrappedProfile).stdout?.trim();
  if (!/^[1-9][0-9]*$/.test(certificateCount) || !Number.isSafeInteger(Number(certificateCount))) {
    throw new Error('profile developer certificate list is missing or empty');
  }
  const profileCertificateSHA256 = [];
  for (let index = 0; index < Number(certificateCount); index++) {
    const encoded = command('plutil', ['-extract', `Profile.DeveloperCertificates.${index}`, 'raw', '-expect', 'data', '-o', '-', '-'], wrappedProfile).stdout;
    if (typeof encoded !== 'string' || !encoded.trim()) throw new Error('empty profile developer certificate');
    const normalized = encoded.replace(/\s/g, '');
    const bytes = Buffer.from(normalized, 'base64');
    if (bytes.toString('base64') !== normalized) throw new Error('malformed profile developer certificate encoding');
    profileCertificateSHA256.push(certificateSHA256(bytes));
  }
  const provisioningEntitlements = profile.Entitlements;
  const errors = [];
  const requireFact = (condition, message) => { if (!condition) errors.push(message); };
  requireFact(profileCertificateSHA256.includes(signerCertificateSHA256),
    'profile does not authorize the actual app signing certificate');
  const team = record.teamIdentifier;
  requireFact(typeof team === 'string' && /^[A-Z0-9]{10}$/.test(team), 'Personal teamIdentifier is required');
  const appIdentifier = `${team}.${bundle}`;
  requireFact(info.CFBundleIdentifier === bundle, 'artifact bundle identifier must be com.taisa.app.personal');
  requireFact(info.TaisaEnvironment === 'personal', 'artifact environment must be personal');
  requireFact(String(info.CFBundleVersion) === record.appBuildNumber, 'artifact app build number mismatch');
  requireFact(String(info.CFBundleShortVersionString) === record.appVersion,
    'artifact app marketing version mismatch');
  requireFact(/^Identifier=(.+)$/m.exec(signature)?.[1] === bundle, 'signature application identifier mismatch');
  requireFact(/^TeamIdentifier=(.+)$/m.exec(signature)?.[1] === team, 'signature team identifier mismatch');
  requireFact(/^Authority=Apple Development:/m.test(signature) && !/^Signature=adhoc$/m.test(signature),
    'Personal signature must use an Apple Development identity');
  requireFact(isDeepStrictEqual(profile.TeamIdentifier, [team]), 'profile team identifier mismatch');
  requireFact(isDeepStrictEqual(profile.ApplicationIdentifierPrefix, [team]), 'profile application identifier prefix mismatch');
  requireFact(typeof profile.UUID === 'string' && /^[0-9a-f-]{36}$/i.test(profile.UUID), 'profile UUID is required');
  const expiry = typeof profile.ExpirationDate === 'string' ? Date.parse(profile.ExpirationDate) : NaN;
  requireFact(Number.isFinite(expiry) && expiry > now.getTime(), 'profile expiration is invalid or expired');
  requireFact(Array.isArray(profile.ProvisionedDevices) && profile.ProvisionedDevices.includes(record.deviceIdentifier),
    'profile does not authorize the recorded device identifier');
  requireFact(profile.ProvisionsAllDevices !== true, 'Personal profile must authorize explicit device identifiers');
  for (const [name, rights] of Object.entries({ signedEntitlements, provisioningEntitlements })) {
    requireFact(object(rights), `${name} identity dictionary is required`);
    requireFact(rights?.['application-identifier'] === appIdentifier, `${name} application-identifier mismatch or missing`);
    requireFact(rights?.['com.apple.developer.team-identifier'] === team, `${name} team-identifier mismatch or missing`);
    requireFact(rights?.['get-task-allow'] === true, `${name} must authorize development debugging`);
    for (const key of Object.keys(object(rights) ? rights : {})) {
      if (forbidden.test(key)) errors.push(`forbidden Personal capability in ${name}: ${key}`);
    }
  }
  const backgroundModes = info.UIBackgroundModes ?? [];
  requireFact(Array.isArray(backgroundModes) && backgroundModes.length === 0, 'Personal artifact background modes must be empty');
  requireFact(typeof record.candidateCommit === 'string' && /^[a-f0-9]{40}$/i.test(record.candidateCommit), 'Personal candidate must be a full Git commit');
  const images = [], linkedLibraries = new Set();
  let candidateFound = false, contractFound = false;
  for (const file of bundleFiles(appPath)) {
    const bytes = readFileSync(file);
    if (!isMachO(bytes)) continue;
    candidateFound ||= bytes.includes(Buffer.from(record.candidateCommit ?? ''));
    contractFound ||= bytes.includes(Buffer.from(record.contractRevision ?? ''));
    const output = command('otool', ['-L', file]).stdout;
    if (typeof output !== 'string' || !output.trim()) throw new Error('empty linkage inspection');
    const libraries = [...output.matchAll(/^\s+(\S+)\s+\(compatibility version /gm)].map(match => match[1]);
    if (!libraries.length) throw new Error('empty linkage dependency list');
    for (const library of libraries) linkedLibraries.add(library);
    const symbols = command('nm', ['-g', file]).stdout;
    requireFact(!liveTransport.test(output + symbols + bytes.toString('latin1')), 'Personal artifact contains live transport');
    images.push({ path: file.slice(appPath.length + 1), sha256: sha256(bytes), linkedLibraries: libraries });
  }
  requireFact(candidateFound, 'artifact candidate commit bytes mismatch or missing');
  requireFact(contractFound, 'artifact contract revision bytes mismatch or missing');
  // Detect replacement while inspection ran; the signature seal covers all bundle resources.
  requireFact(sha256(regularFile(profilePath)) === sha256(profileBytes), 'profile artifact changed during inspection');
  requireFact(sha256(regularFile(infoPath)) === sha256(infoBytes), 'Info.plist artifact changed during inspection');
  for (const image of images) requireFact(sha256(regularFile(join(appPath, image.path))) === image.sha256, 'executable artifact changed during inspection');
  command('codesign', ['--verify', '--deep', '--strict', appPath]);
  const artifactEvidence = { executable, teamIdentifier: team, signerCertificateSHA256,
    profileUUID: profile.UUID, profileExpiration: profile.ExpirationDate,
    profileSHA256: sha256(profileBytes), infoPlistSHA256: sha256(infoBytes), images,
    inspectedAt: now.toISOString(), signatureVerified: true,
    attestationType: 'live-artifact-inspection' };
  const evidence = { signedEntitlements, provisioningEntitlements, backgroundModes,
    linkedLibraries: [...linkedLibraries].sort(), linksLiveTransport: false, artifactEvidence };
  for (const [field, value] of Object.entries(evidence)) {
    const supplied = field === 'artifactEvidence'
      ? evidenceWithoutInspectionTime(record[field]) : record[field];
    const inspected = field === 'artifactEvidence'
      ? evidenceWithoutInspectionTime(value) : value;
    if (Object.hasOwn(record, field) && !isDeepStrictEqual(supplied, inspected)) {
      errors.push(`caller ${field} disagrees with inspected artifact`);
    }
  }
  return { errors, evidence: { ...evidence, appPath, profilePath,
    evidenceValidation: {
      mode: 'live-artifact-reinspection',
      liveReinspectionPerformed: true,
      statement: 'The signed artifact was cryptographically reinspected during this validation.',
    } } };
}

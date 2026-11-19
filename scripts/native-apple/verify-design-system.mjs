import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { lstat, readdir, readFile, realpath } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const RAW_COLOR_PATTERN = /#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?/g;
export const nativeControlRoots = [
  'apple/TaisaApp',
  'apple/Packages/TaisaFoundation/Sources',
];

async function swiftFiles(root) {
  const entries = await readdir(root, { withFileTypes: true });
  const files = await Promise.all(entries.map(async (entry) => {
    const target = path.join(root, entry.name);
    if (entry.isDirectory()) return swiftFiles(target);
    if (entry.isSymbolicLink()) throw new Error(`Symlinked source is not classifiable: ${target}`);
    return entry.isFile() && entry.name.endsWith('.swift') ? [target] : [];
  }));
  return files.flat();
}

function sanitizeSwift(source) {
  const masked = source.split('');
  const blank = (index) => { if (masked[index] !== '\n' && masked[index] !== '\r') masked[index] = ' '; };
  let index = 0;
  let blockDepth = 0;

  while (index < source.length) {
    if (blockDepth > 0) {
      if (source.startsWith('/*', index)) {
        blank(index); blank(index + 1); blockDepth += 1; index += 2;
      } else if (source.startsWith('*/', index)) {
        blank(index); blank(index + 1); blockDepth -= 1; index += 2;
      } else {
        blank(index); index += 1;
      }
      continue;
    }
    if (source.startsWith('//', index)) {
      while (index < source.length && source[index] !== '\n') { blank(index); index += 1; }
      continue;
    }
    if (source.startsWith('/*', index)) {
      blank(index); blank(index + 1); blockDepth = 1; index += 2; continue;
    }

    let hashes = 0;
    while (source[index + hashes] === '#') hashes += 1;
    const quoteIndex = index + hashes;
    if (source[quoteIndex] === '"') {
      const quoteCount = source.startsWith('"""', quoteIndex) ? 3 : 1;
      const openingLength = hashes + quoteCount;
      for (let offset = 0; offset < openingLength; offset += 1) blank(index + offset);
      index += openingLength;
      const closing = `${'"'.repeat(quoteCount)}${'#'.repeat(hashes)}`;
      let escaped = false;
      while (index < source.length) {
        if (!escaped && source.startsWith(closing, index)) {
          for (let offset = 0; offset < closing.length; offset += 1) blank(index + offset);
          index += closing.length;
          break;
        }
        const character = source[index];
        blank(index);
        if (hashes === 0 && quoteCount === 1) {
          if (escaped) escaped = false;
          else if (character === '\\') escaped = true;
        }
        index += 1;
      }
      continue;
    }
    index += 1;
  }
  return masked.join('');
}

function occurrenceKey(occurrence) {
  return [
    occurrence.file,
    occurrence.constructor,
    occurrence.line,
    occurrence.column,
    occurrence.sourceHash,
  ].join(':');
}

function sourceFileHash(source) {
  return createHash('sha256').update(source).digest('hex');
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function constructorPattern(constructor) {
  return new RegExp(
    `(?<![A-Za-z0-9_])(?:SwiftUI\\s*\\.\\s*)?\\x60?${escapeRegExp(constructor)}\\x60?`
      + '(?:\\s*<[^>{}\\n]+>)?(?:\\s*\\.\\s*init)?\\s*(?=[({])',
    'g',
  );
}

export async function rawInteractiveControlOccurrences({ roots, repositoryRoot = process.cwd(), constructors }) {
  const occurrences = [];
  for (const relativeRoot of roots) {
    const absoluteRoot = path.resolve(repositoryRoot, relativeRoot);
    for (const absoluteFile of await swiftFiles(absoluteRoot)) {
      const source = await readFile(absoluteFile, 'utf8');
      const sanitized = sanitizeSwift(source);
      const relativeFile = path.relative(repositoryRoot, absoluteFile);
      for (const constructor of constructors) {
        const pattern = constructorPattern(constructor);
        for (const match of sanitized.matchAll(pattern)) {
          const prefix = source.slice(0, match.index);
          const line = prefix.split('\n').length;
          const lineStart = prefix.lastIndexOf('\n') + 1;
          const column = match.index - lineStart + 1;
          occurrences.push({
            file: relativeFile,
            constructor,
            line,
            column,
            sourceHash: sourceFileHash(source),
          });
        }
      }
    }
  }
  return occurrences;
}

async function loadControlPolicy(policyPath) {
  const policy = JSON.parse(await readFile(policyPath, 'utf8'));
  if (!Array.isArray(policy.controlledConstructors)
      || !Array.isArray(policy.primitiveFiles)
      || !Array.isArray(policy.legacyOccurrences)) {
    throw new Error('Control policy requires controlledConstructors, primitiveFiles, and legacyOccurrences arrays.');
  }
  if (policy.controlledConstructors.length === 0
      || new Set(policy.controlledConstructors).size !== policy.controlledConstructors.length
      || policy.controlledConstructors.some((value) => typeof value !== 'string' || value.length === 0)) {
    throw new Error('Control policy requires unique non-empty controlled constructors.');
  }
  if (new Set(policy.primitiveFiles).size !== policy.primitiveFiles.length
      || policy.primitiveFiles.some((value) => typeof value !== 'string' || value.length === 0)) {
    throw new Error('Control policy requires unique non-empty primitive file paths.');
  }
  const legacyKeys = new Set();
  for (const entry of policy.legacyOccurrences) {
    const valid = entry && typeof entry.file === 'string'
      && policy.controlledConstructors.includes(entry.constructor)
      && Number.isInteger(entry.line) && entry.line > 0
      && Number.isInteger(entry.column) && entry.column > 0
      && typeof entry.sourceHash === 'string' && /^[0-9a-f]{64}$/.test(entry.sourceHash)
      && typeof entry.owner === 'string' && entry.owner.trim().length > 0
      && typeof entry.reason === 'string' && entry.reason.trim().length > 0;
    if (!valid) throw new Error('Every legacy occurrence requires valid fields, owner, and semantic reason.');
    const key = occurrenceKey(entry);
    if (legacyKeys.has(key)) throw new Error(`Control policy contains duplicate legacy occurrence: ${key}`);
    legacyKeys.add(key);
  }
  return policy;
}

export async function rawInteractiveControlViolations({
  roots,
  policyPath,
  repositoryRoot = process.cwd(),
}) {
  const policy = await loadControlPolicy(policyPath);
  const dsRoot = path.resolve(repositoryRoot, 'apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem');
  const canonicalDSRoot = policy.primitiveFiles.length > 0 ? await realpath(dsRoot) : dsRoot;
  for (const primitiveFile of policy.primitiveFiles) {
    const absoluteFile = path.resolve(repositoryRoot, primitiveFile);
    const canonicalFile = await realpath(absoluteFile);
    const metadata = await lstat(absoluteFile);
    if (!absoluteFile.startsWith(`${dsRoot}${path.sep}`)
        || !canonicalFile.startsWith(`${canonicalDSRoot}${path.sep}`)
        || metadata.isSymbolicLink() || !metadata.isFile() || path.extname(absoluteFile) !== '.swift') {
      throw new Error(`Primitive file must be a canonical regular Swift file inside the canonical design-system source root: ${primitiveFile}`);
    }
    const source = await readFile(absoluteFile, 'utf8');
    const publicStructs = [...source.matchAll(/\bpublic\s+struct\s+([A-Za-z_][A-Za-z0-9_]*)/g)].map((match) => match[1]);
    const expectedType = path.basename(absoluteFile, '.swift');
    if (publicStructs.length !== 1 || publicStructs[0] !== expectedType) {
      throw new Error(`Primitive file must be dedicated to public struct ${expectedType}: ${primitiveFile}`);
    }
  }

  const occurrences = await rawInteractiveControlOccurrences({
    roots,
    repositoryRoot,
    constructors: policy.controlledConstructors,
  });
  const primitiveFiles = new Set(policy.primitiveFiles);
  const approvedLegacy = new Map(policy.legacyOccurrences.map((entry) => [occurrenceKey(entry), entry]));
  const observedLegacyKeys = new Set();
  const violations = [];

  for (const occurrence of occurrences) {
    if (primitiveFiles.has(occurrence.file)) continue;
    const key = occurrenceKey(occurrence);
    if (approvedLegacy.has(key)) {
      observedLegacyKeys.add(key);
      continue;
    }
    violations.push({ kind: 'unclassified-control', ...occurrence });
  }

  for (const entry of policy.legacyOccurrences) {
    const key = occurrenceKey(entry);
    if (!observedLegacyKeys.has(key)) {
      violations.push({ kind: 'stale-legacy-occurrence', ...entry });
    }
  }
  return violations;
}

export async function rawVisualValues(root) {
  const violations = [];
  for (const file of await swiftFiles(root)) {
    const source = await readFile(file, 'utf8');
    for (const match of source.matchAll(RAW_COLOR_PATTERN)) {
      violations.push({
        file,
        line: source.slice(0, match.index).split('\n').length,
        value: match[0],
      });
    }
  }
  return violations;
}

/// Audits explicit Product presentation and its transitive shared implementation.
/// This is intentionally stricter than font inheritance: an inherited body font
/// cannot establish the intended label, metadata, field, or title role.
export async function surfaceAdoptionViolations({ repositoryRoot = process.cwd(), productFiles, sharedSourceFiles = [] }) {
  const dsRoot = 'apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem';
  const sharedFiles = await swiftFiles(path.join(repositoryRoot, dsRoot));
  const sources = new Map();
  const definitions = new Map();
  for (const file of sharedFiles) {
    const relative = path.relative(repositoryRoot, file);
    const source = await readFile(file, 'utf8');
    sources.set(relative, source);
    for (const match of sanitizeSwift(source).matchAll(/\b(?:struct|enum|class|typealias)\s+((?:Taisa|CentralIcon)\w*)/g)) {
      const owners = definitions.get(match[1]) ?? new Set();
      owners.add(relative);
      definitions.set(match[1], owners);
    }
  }
  const sharedPresentation = await rawInteractiveControlOccurrences({
    roots: [dsRoot], repositoryRoot, constructors: ['Text', 'Label', 'LabeledContent'],
  });
  const queue = [...productFiles, ...sharedSourceFiles];
  const visited = new Set();
  const violations = [];
  while (queue.length) {
    const file = queue.shift();
    if (visited.has(file)) continue;
    visited.add(file);
    const source = sources.get(file) ?? await readFile(path.resolve(repositoryRoot, file), 'utf8');
    const code = sanitizeSwift(source);
    for (const reference of code.matchAll(/\b(?:Taisa|CentralIcon)\w*/g)) {
      for (const dependency of definitions.get(reference[0]) ?? []) queue.push(dependency);
    }
    const product = productFiles.includes(file);
    if (product) {
      for (const constructor of ['ProgressView', 'Section', 'Toggle', 'Picker', 'DatePicker', 'ContentUnavailableView', 'NavigationLink']) {
        for (const match of code.matchAll(constructorPattern(constructor))) {
          const opening = match.index + match[0].length;
          if (code[opening] !== '(') continue;
          const argumentsCode = code.slice(opening + 1).trimStart();
          // Positional labels may be literals, variables, or expressions. Named
          // value/selection arguments and explicit label closures do not select
          // the implicit system-label overload. Sanitized literals are blank,
          // so inspect the original argument before accepting an empty call.
          const argumentsSource = source.slice(opening + 1).trimStart();
          const emptyCall = argumentsSource.startsWith(')');
          const namedArgument = /^[A-Za-z_]\w*\s*:/.test(argumentsCode);
          if (!emptyCall && !namedArgument) {
            violations.push({ kind: 'implicit-product-presentation', file, constructor });
          }
        }
      }
      const occurrences = await rawInteractiveControlOccurrences({
        roots: [path.dirname(file)], repositoryRoot,
        constructors: ['Text', 'Button', 'Label', 'TextField', 'SecureField', 'LabeledContent'],
      });
      for (const occurrence of occurrences.filter(value => value.file === file)) {
        violations.push({ kind: 'implicit-product-presentation', ...occurrence });
      }
    } else {
      if (!file.endsWith('/TaisaText.swift') && sharedPresentation.some(occurrence => occurrence.file === file)) {
        violations.push({ kind: 'implicit-shared-presentation', file });
      }
    }
    {
      const kind = product ? 'raw-product-typography' : 'raw-shared-typography';
      if (!product && file.endsWith('/TypographyToken.swift')) {
        if (/\.system\s*\(/.test(code)) violations.push({ kind: 'system-font-token', file });
      } else {
        const rawFont = /\.(?:fontWeight|bold|custom|system)\s*\(/.test(code);
        if (rawFont) violations.push({ kind, file });
        for (const call of code.matchAll(/\.font\s*\(/g)) {
          let depth = 1;
          let end = call.index + call[0].length;
          const start = end;
          while (end < code.length && depth > 0) {
            if (code[end] === '(') depth++;
            if (code[end] === ')') depth--;
            end++;
          }
          const argument = code.slice(start, end - 1).trim();
          const directRole = /^TaisaTypography\.\w+\.font$/.test(argument);
          const textRole = file.endsWith('/TaisaText.swift') && argument === 'role.font';
          const conditionalRoles = /^[\w.\s=!]+\?\s*TaisaTypography\.\w+\.font\s*:\s*TaisaTypography\.\w+\.font$/.test(argument);
          if (!directRole && !textRole && !conditionalRoles) {
            violations.push({ kind, file, value: argument });
          }
        }
      }
    }
  }
  return violations;
}

export function auditedProductFiles(registeredFiles, changedFiles) {
  return [...new Set([...registeredFiles, ...changedFiles.filter(file =>
    file.startsWith('apple/TaisaApp/') && file.endsWith('.swift'))])];
}

export function legacyDebtRetirementViolations(legacyOccurrences, changedFiles) {
  const changed = new Set(changedFiles);
  return legacyOccurrences.filter(entry => changed.has(entry.file))
    .map(entry => ({ kind: 'changed-surface-legacy-debt', ...entry }));
}

async function main() {
  const visualViolations = await rawVisualValues('apple/TaisaApp');
  if (visualViolations.length > 0) {
    console.error('Raw color values found in app views:');
    for (const violation of visualViolations) {
      console.error(`- ${violation.file}:${violation.line} ${violation.value}`);
    }
    process.exitCode = 1;
    return;
  }

  const controlViolations = await rawInteractiveControlViolations({
    roots: nativeControlRoots,
    policyPath: 'scripts/native-apple/design-system-control-policy.json',
  });
  if (controlViolations.length > 0) {
    console.error('Unapproved or stale raw interactive-control classifications found:');
    for (const violation of controlViolations) {
      console.error(`- ${violation.kind} ${violation.file}:${violation.line}:${violation.column} ${violation.constructor}`);
    }
    process.exitCode = 1;
    return;
  }
  const surfacePolicy = JSON.parse(await readFile('scripts/native-apple/design-system-surface-policy.json', 'utf8'));
  if (!Array.isArray(surfacePolicy.productFiles) || surfacePolicy.productFiles.length === 0
      || new Set(surfacePolicy.productFiles).size !== surfacePolicy.productFiles.length
      || surfacePolicy.productFiles.some(file => typeof file !== 'string' || !file.startsWith('apple/TaisaApp/') || file.includes('..') || !file.endsWith('.swift'))) {
    throw new Error('Surface policy requires unique canonical Product Swift file paths.');
  }
  // Compare to the PR base, not HEAD: a committed fingerprint refresh must not
  // turn changed legacy Product/composite code into approved adoption.
  const baseRef = process.env.TAISA_DS_BASE_REF || 'origin/main';
  const changedFiles = [
    ...execFileSync('git', ['diff', '--name-only', '--diff-filter=ACMR', baseRef, '--'], { encoding: 'utf8' }).trim().split('\n'),
    ...execFileSync('git', ['ls-files', '--others', '--exclude-standard'], { encoding: 'utf8' }).trim().split('\n'),
  ];
  const surfaceViolations = await surfaceAdoptionViolations({
    productFiles: auditedProductFiles(surfacePolicy.productFiles, changedFiles),
    sharedSourceFiles: changedFiles.filter(file => file.startsWith('apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/') && file.endsWith('.swift')),
  });
  const policy = await loadControlPolicy('scripts/native-apple/design-system-control-policy.json');
  const debtViolations = legacyDebtRetirementViolations(policy.legacyOccurrences, changedFiles);
  const adoptionViolations = [...surfaceViolations, ...debtViolations];
  if (adoptionViolations.length) {
    for (const violation of adoptionViolations) console.error(`- ${violation.kind} ${violation.file}`);
    process.exitCode = 1;
    return;
  }
  console.log('Native design-system verification passed (registered surfaces and transitive shared contracts; unchanged legacy debt remains separately tracked).');
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await main();
}

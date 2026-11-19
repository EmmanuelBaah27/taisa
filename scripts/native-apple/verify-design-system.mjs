import { createHash } from 'node:crypto';
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
  const blankRange = (start, length) => {
    for (let offset = 0; offset < length; offset += 1) blank(start + offset);
  };

  const consumeRegex = (start, hashes) => {
    const openingLength = hashes + 1;
    blankRange(start, openingLength);
    let cursor = start + openingLength;
    let escaped = false;
    const closing = `/${'#'.repeat(hashes)}`;
    while (cursor < source.length) {
      if (!escaped && source.startsWith(closing, cursor)) {
        blankRange(cursor, closing.length);
        return cursor + closing.length;
      }
      const character = source[cursor];
      blank(cursor);
      if (escaped) escaped = false;
      else if (character === '\\') escaped = true;
      cursor += 1;
    }
    return cursor;
  };

  let consumeString;
  const consumeInterpolation = (start) => {
    let cursor = start;
    let depth = 1;
    while (cursor < source.length && depth > 0) {
      if (source.startsWith('//', cursor)) {
        while (cursor < source.length && source[cursor] !== '\n') { blank(cursor); cursor += 1; }
        continue;
      }
      if (source.startsWith('/*', cursor)) {
        let commentDepth = 1;
        blankRange(cursor, 2);
        cursor += 2;
        while (cursor < source.length && commentDepth > 0) {
          if (source.startsWith('/*', cursor)) {
            blankRange(cursor, 2); commentDepth += 1; cursor += 2;
          } else if (source.startsWith('*/', cursor)) {
            blankRange(cursor, 2); commentDepth -= 1; cursor += 2;
          } else {
            blank(cursor); cursor += 1;
          }
        }
        continue;
      }

      let hashes = 0;
      while (source[cursor + hashes] === '#') hashes += 1;
      const delimiterIndex = cursor + hashes;
      if (hashes > 0 && source[delimiterIndex] === '/') {
        cursor = consumeRegex(cursor, hashes);
        continue;
      }
      if (source[delimiterIndex] === '"') {
        cursor = consumeString(cursor, hashes);
        continue;
      }
      if (source[cursor] === '(') depth += 1;
      else if (source[cursor] === ')') depth -= 1;
      blank(cursor);
      cursor += 1;
    }
    return cursor;
  };

  consumeString = (start, hashes) => {
    const quoteIndex = start + hashes;
    const quoteCount = source.startsWith('"""', quoteIndex) ? 3 : 1;
    const openingLength = hashes + quoteCount;
    blankRange(start, openingLength);
    let cursor = start + openingLength;
    const closing = `${'"'.repeat(quoteCount)}${'#'.repeat(hashes)}`;
    const interpolation = `\\${'#'.repeat(hashes)}(`;
    let escaped = false;
    while (cursor < source.length) {
      if (!escaped && source.startsWith(closing, cursor)) {
        blankRange(cursor, closing.length);
        return cursor + closing.length;
      }
      if (!escaped && source.startsWith(interpolation, cursor)) {
        blankRange(cursor, interpolation.length);
        cursor = consumeInterpolation(cursor + interpolation.length);
        escaped = false;
        continue;
      }
      const character = source[cursor];
      blank(cursor);
      if (hashes === 0) {
        if (escaped) escaped = false;
        else if (character === '\\') escaped = true;
      }
      cursor += 1;
    }
    return cursor;
  };

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
    const delimiterIndex = index + hashes;
    if (hashes > 0 && source[delimiterIndex] === '/') {
      index = consumeRegex(index, hashes);
      continue;
    }
    if (source[delimiterIndex] === '"') {
      index = consumeString(index, hashes);
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

export async function rawInteractiveControlOccurrences({ roots, repositoryRoot = process.cwd(), constructors }) {
  const occurrences = [];
  for (const relativeRoot of roots) {
    const absoluteRoot = path.resolve(repositoryRoot, relativeRoot);
    for (const absoluteFile of await swiftFiles(absoluteRoot)) {
      const source = await readFile(absoluteFile, 'utf8');
      const sanitized = sanitizeSwift(source);
      const relativeFile = path.relative(repositoryRoot, absoluteFile);
      for (const constructor of constructors) {
        const name = escapeRegExp(constructor);
        const pattern = new RegExp(
          `(?<![A-Za-z0-9_])(?:SwiftUI\\s*\\.\\s*)?\\x60?${name}\\x60?`,
          'g',
        );
        for (const match of sanitized.matchAll(pattern)) {
          let cursor = match.index + match[0].length;
          while (/\s/.test(sanitized[cursor] ?? '')) cursor += 1;
          if (sanitized[cursor] === '<') {
            let depth = 0;
            do {
              if (sanitized[cursor] === '<') depth += 1;
              else if (sanitized[cursor] === '>') depth -= 1;
              cursor += 1;
            } while (cursor < sanitized.length && depth > 0);
            if (depth !== 0) continue;
            while (/\s/.test(sanitized[cursor] ?? '')) cursor += 1;
          }
          const initializer = sanitized.slice(cursor).match(/^\.\s*init\b/);
          if (initializer) {
            cursor += initializer[0].length;
            while (/\s/.test(sanitized[cursor] ?? '')) cursor += 1;
          }
          if (sanitized[cursor] !== '(' && sanitized[cursor] !== '{') continue;
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
  console.log('Native design-system verification passed.');
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await main();
}

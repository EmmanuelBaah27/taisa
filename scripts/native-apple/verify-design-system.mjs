import { createHash } from 'node:crypto';
import { access, readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const RAW_COLOR_PATTERN = /#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?/g;

async function swiftFiles(root) {
  const entries = await readdir(root, { withFileTypes: true });
  const files = await Promise.all(entries.map(async (entry) => {
    const target = path.join(root, entry.name);
    if (entry.isDirectory()) return swiftFiles(target);
    return entry.isFile() && entry.name.endsWith('.swift') ? [target] : [];
  }));
  return files.flat();
}

function sanitizeSwift(source) {
  const characters = [...source];
  let state = 'code';
  let escaped = false;

  for (let index = 0; index < characters.length; index += 1) {
    const character = characters[index];
    const next = characters[index + 1];

    if (state === 'line-comment') {
      if (character === '\n') state = 'code';
      else characters[index] = ' ';
      continue;
    }
    if (state === 'block-comment') {
      if (character === '*' && next === '/') {
        characters[index] = ' ';
        characters[index + 1] = ' ';
        index += 1;
        state = 'code';
      } else if (character !== '\n') characters[index] = ' ';
      continue;
    }
    if (state === 'string') {
      if (character !== '\n') characters[index] = ' ';
      if (escaped) escaped = false;
      else if (character === '\\') escaped = true;
      else if (character === '"') state = 'code';
      continue;
    }
    if (character === '/' && next === '/') {
      characters[index] = ' ';
      characters[index + 1] = ' ';
      index += 1;
      state = 'line-comment';
    } else if (character === '/' && next === '*') {
      characters[index] = ' ';
      characters[index + 1] = ' ';
      index += 1;
      state = 'block-comment';
    } else if (character === '"') {
      characters[index] = ' ';
      state = 'string';
    }
  }
  return characters.join('');
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

function sourceLineHash(line) {
  return createHash('sha256').update(line.trim()).digest('hex');
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
        const pattern = new RegExp(`\\b${constructor}\\s*\\(`, 'g');
        for (const match of sanitized.matchAll(pattern)) {
          const prefix = source.slice(0, match.index);
          const line = prefix.split('\n').length;
          const lineStart = prefix.lastIndexOf('\n') + 1;
          const column = match.index - lineStart + 1;
          const sourceLine = source.split('\n')[line - 1] ?? '';
          occurrences.push({
            file: relativeFile,
            constructor,
            line,
            column,
            sourceHash: sourceLineHash(sourceLine),
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
  return policy;
}

export async function rawInteractiveControlViolations({
  roots,
  policyPath,
  repositoryRoot = process.cwd(),
}) {
  const policy = await loadControlPolicy(policyPath);
  const dsRoot = 'apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/';
  for (const primitiveFile of policy.primitiveFiles) {
    if (!primitiveFile.startsWith(dsRoot) || !primitiveFile.endsWith('.swift')) {
      throw new Error(`Primitive file must be an exact Swift file beneath ${dsRoot}: ${primitiveFile}`);
    }
    await access(path.resolve(repositoryRoot, primitiveFile));
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
    roots: [
      'apple/TaisaApp',
      'apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem',
    ],
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

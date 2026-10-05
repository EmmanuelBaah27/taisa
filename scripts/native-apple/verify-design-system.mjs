import { readdir, readFile } from 'node:fs/promises';
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
  const violations = await rawVisualValues('apple/TaisaApp');
  if (violations.length > 0) {
    console.error('Raw color values found in app views:');
    for (const violation of violations) {
      console.error(`- ${violation.file}:${violation.line} ${violation.value}`);
    }
    process.exitCode = 1;
    return;
  }
  console.log('Native design-system verification passed.');
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await main();
}

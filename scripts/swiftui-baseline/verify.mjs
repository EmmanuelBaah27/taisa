import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { validateManifest } from './lib.mjs';

function evidenceRootFrom(argv) {
  const index = argv.indexOf('--evidence-root');
  return index === -1 ? 'docs/migration/swiftui' : argv[index + 1];
}

const evidenceRoot = resolve(evidenceRootFrom(process.argv.slice(2)));
const manifest = JSON.parse(await readFile(resolve(evidenceRoot, 'baseline-manifest.json'), 'utf8'));
const errors = validateManifest(manifest);

if (errors.length) {
  process.stderr.write(`${errors.join('\n')}\n`);
  process.exitCode = 1;
} else {
  process.stdout.write('Baseline evidence verification passed.\n');
}

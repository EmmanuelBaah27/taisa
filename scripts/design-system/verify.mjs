import { readFile } from 'node:fs/promises';
import { dirname, extname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

import { PRODUCT_EXTENSIONS, RULES } from './rules.mjs';

const scriptRoot = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptRoot, '../..');

function lineFor(contents, index) {
  return contents.slice(0, index).split('\n').length;
}

function validateException(exception, today) {
  for (const field of ['file', 'rule', 'reason', 'owner', 'expires']) {
    if (typeof exception[field] !== 'string' || exception[field].trim() === '') {
      return `exception-invalid: missing ${field}`;
    }
  }
  if (/[*?\[\]]/.test(exception.file) || exception.file.endsWith('/')) {
    return 'exception-invalid: file must be an exact path';
  }
  if (exception.expires < today) return 'exception-expired';
  return null;
}

export async function verifyPaths({ root, paths, exceptions = [], today = new Date().toISOString().slice(0, 10) }) {
  const findings = [];
  const matchedExceptions = new Set();
  const exceptionProblems = new Map();

  exceptions.forEach((exception, index) => {
    const problem = validateException(exception, today);
    if (problem) exceptionProblems.set(index, problem);
  });

  for (const file of [...paths].sort()) {
    if (!PRODUCT_EXTENSIONS.has(extname(file))) continue;
    const contents = await readFile(join(root, file), 'utf8');
    for (const rule of RULES) {
      // The semantic Text primitive must wrap React Native's Text. Keep this
      // bootstrap boundary explicit instead of weakening the repository rule.
      if (file === 'mobile/src/components/ui/Text.tsx' && rule.id === 'semantic-text-only') continue;
      for (const match of contents.matchAll(new RegExp(rule.pattern.source, rule.pattern.flags))) {
        const exceptionIndex = exceptions.findIndex((entry) => entry.file === file && entry.rule === rule.id);
        if (exceptionIndex >= 0) {
          matchedExceptions.add(exceptionIndex);
          const problem = exceptionProblems.get(exceptionIndex);
          if (!problem) continue;
          findings.push({ file, line: lineFor(contents, match.index ?? 0), rule: problem.split(':')[0], message: problem });
          continue;
        }
        findings.push({ file, line: lineFor(contents, match.index ?? 0), rule: rule.id, message: rule.message });
      }
    }
  }

  exceptions.forEach((exception, index) => {
    if (!matchedExceptions.has(index) && !exceptionProblems.has(index)) {
      findings.push({ file: exception.file, line: 1, rule: 'exception-unused', message: 'Exception matches no current finding.' });
    }
  });

  return findings.sort((a, b) => a.file.localeCompare(b.file) || a.line - b.line || a.rule.localeCompare(b.rule));
}

async function componentRegistryFindings(root, registry) {
  const findings = [];
  const barrel = await readFile(join(root, 'mobile/src/components/ui/index.ts'), 'utf8');
  const docs = await readFile(join(root, 'docs/design-system.md'), 'utf8');
  for (const component of registry.components) {
    try {
      await readFile(join(root, component.implementation), 'utf8');
    } catch {
      findings.push({ file: component.implementation, line: 1, rule: 'component-implementation', message: 'Registered component implementation is missing.' });
    }
    if (!barrel.includes(`{ ${component.name}`) && !barrel.includes(`, ${component.name}`)) {
      findings.push({ file: 'mobile/src/components/ui/index.ts', line: 1, rule: 'component-export', message: `${component.name} is not exported from the UI barrel.` });
    }
    if (!docs.includes(`\`${component.name}\``)) {
      findings.push({ file: 'docs/design-system.md', line: 1, rule: 'component-docs', message: `${component.name} is not documented.` });
    }
    if (component.storyRequired) {
      try {
        const story = await readFile(join(root, component.story), 'utf8');
        const productionImport = new RegExp(`import \\{[^}]*\\b${component.name}\\b[^}]*\\} from '\\./${component.name}'`);
        const componentBinding = new RegExp(`component:\\s*${component.name}\\b`);
        if (!productionImport.test(story) || !componentBinding.test(story)) {
          findings.push({
            file: component.story,
            line: 1,
            rule: 'storybook-production-parity',
            message: `${component.name} story must bind meta.component to the exact production export.`,
          });
        }
      } catch {
        findings.push({ file: component.story, line: 1, rule: 'component-story', message: `${component.name} requires Storybook coverage.` });
      }
    }
  }
  return findings;
}

async function repositoryPaths(root) {
  const output = execFileSync('git', ['ls-files', 'mobile/app', 'mobile/src/components'], { cwd: root, encoding: 'utf8' });
  return output.split('\n').filter(Boolean).filter((file) => !file.includes('/.rnstorybook/'));
}

export async function verifyRepository(root = repositoryRoot) {
  const exceptions = JSON.parse(await readFile(join(root, 'scripts/design-system/exceptions.json'), 'utf8'));
  const registry = JSON.parse(await readFile(join(root, 'scripts/design-system/component-registry.json'), 'utf8'));
  const findings = await verifyPaths({ root, paths: await repositoryPaths(root), exceptions });
  findings.push(...await componentRegistryFindings(root, registry));
  return findings.sort((a, b) => a.file.localeCompare(b.file) || a.line - b.line || a.rule.localeCompare(b.rule));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const findings = await verifyRepository();
  if (findings.length > 0) {
    for (const finding of findings) console.error(`${finding.file}:${finding.line} ${finding.rule} ${finding.message}`);
    process.exit(1);
  } else {
    console.log('Design-system verification passed.');
  }
}

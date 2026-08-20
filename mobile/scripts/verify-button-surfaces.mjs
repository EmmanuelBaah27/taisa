import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const mobileRoot = join(fileURLToPath(new URL('.', import.meta.url)), '..');
const appRoot = join(mobileRoot, 'app');

const allowedContentSurfaces = new Map([
  ['app/(tabs)/you.tsx', [
    'setGoalsInput',
    'setRoleInput',
    "setRecoveryMode('export')",
    'chooseArchiveToRestore',
  ]],
]);

function sourceFiles(directory) {
  return readdirSync(directory).flatMap((entry) => {
    const path = join(directory, entry);
    if (statSync(path).isDirectory()) return sourceFiles(path);
    return path.endsWith('.tsx') ? [path] : [];
  });
}

const violations = [];
const legacyPressable = /<(Pressable|TouchableOpacity|TouchableWithoutFeedback)\b[\s\S]*?>/g;

for (const path of sourceFiles(appRoot)) {
  const source = readFileSync(path, 'utf8');
  const file = relative(mobileRoot, path);
  const allowedFragments = allowedContentSurfaces.get(file) ?? [];

  for (const match of source.matchAll(legacyPressable)) {
    const openingTag = match[0];
    const localContext = source.slice(match.index, match.index + 500);
    if (!openingTag.includes('onPress')) continue;
    if (allowedFragments.some((fragment) => localContext.includes(fragment))) continue;

    const line = source.slice(0, match.index).split('\n').length;
    violations.push(`${file}:${line} routes an explicit action outside the Design System glass owners`);
  }
}

if (violations.length > 0) {
  process.stderr.write(`${violations.join('\n')}\n`);
  process.exit(1);
}

process.stdout.write('Button-surface verification passed.\n');

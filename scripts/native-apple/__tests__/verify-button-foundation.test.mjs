import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';

const ds = 'apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem';
async function files(root) {
  const entries = await readdir(root, { withFileTypes: true });
  return (await Promise.all(entries.map(entry => entry.isDirectory()
    ? files(path.join(root, entry.name))
    : entry.name.endsWith('.swift') ? [path.join(root, entry.name)] : []))).flat();
}

test('all authored button styles use the shared foundation', async () => {
  const violations = [];
  for (const file of [...await files(ds), ...await files('apple/TaisaApp')]) {
    if (file === `${ds}/TaisaButtonStyle.swift` || file === `${ds}/TaisaButtonControl.swift`) continue;
    const source = await readFile(file, 'utf8');
    for (const call of source.matchAll(/\.buttonStyle\s*\(\s*([^\n]+)/g)) {
      if (!call[1].startsWith('TaisaButtonStyle(')) violations.push(`${file}: ${call[1]}`);
    }
    if (/\.buttonBorderShape\s*\(/.test(source)) violations.push(`${file}: independent button shape`);
    if (/shape\s*:\s*\.roundedRectangle\b/.test(source)) violations.push(`${file}: non-capsule action button`);
  }
  assert.deepEqual(violations, [], 'A button must not replace the shared native treatment');
});

test('record, recovery and floating button wrappers do not author their own glass', async () => {
  for (const file of ['TaisaButton', 'ConversationEntryDock', 'TaisaSecondaryIconButton', 'TaisaSecondaryCapsuleButton', 'ConversationActionBar']) {
    const source = await readFile(`${ds}/${file}.swift`, 'utf8');
    assert.ok(!source.includes('.glassEffect('), `${file} still renders a separate glass button`);
    assert.ok(source.includes('TaisaButtonStyle('), `${file} does not consume the shared foundation`);
  }
  // These two composite surfaces also own a glass navigation/editor background.
  const compositeSurfaces = new Set([`${ds}/PrimaryNavigation.swift`, `${ds}/TextComposer.swift`]);
  for (const file of await files(ds)) {
    const source = await readFile(file, 'utf8');
    if (source.includes('TaisaButtonControl(') && !compositeSurfaces.has(file)) {
      assert.ok(!/\.glassEffect\s*\(/.test(source), `${file} adds another glass renderer around a shared control`);
    }
  }
});

test('both application roots install the same default for all descendant buttons', async () => {
  for (const file of ['apple/TaisaApp/TaisaApp.swift', 'apple/TaisaPreview/TaisaPreviewApp.swift']) {
    const source = await readFile(file, 'utf8');
    assert.ok(source.includes('.buttonStyle(TaisaButtonStyle())'), `${file} lacks the shared button default`);
  }
});

test('only the control constructor and native style may create raw DS buttons', async () => {
  const policy = JSON.parse(await readFile('scripts/native-apple/design-system-control-policy.json', 'utf8'));
  assert.deepEqual(policy.primitiveFiles.slice().sort(), [
    `${ds}/TaisaButtonControl.swift`, `${ds}/TaisaButtonStyle.swift`,
  ]);
  assert.ok(!policy.legacyOccurrences.some(entry => entry.file.startsWith(`${ds}/`)));
  for (const file of await files('apple/TaisaApp')) {
    const source = await readFile(file, 'utf8');
    assert.ok(!/shape\s*:\s*\.roundedRectangle\b/.test(source), `${file} opts out of fully rounded buttons`);
  }
});

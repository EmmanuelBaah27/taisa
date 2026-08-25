import assert from 'node:assert/strict';
import test from 'node:test';
import { readFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const registry = JSON.parse(await readFile(join(root, 'scripts/design-system/component-registry.json'), 'utf8'));

test('Storybook preview consumes production color tokens', async () => {
  const preview = await readFile(join(root, 'mobile/.rnstorybook/preview.tsx'), 'utf8');
  assert.match(preview, /import \{ colorTokens \} from '\.\.\/src\/design-system\/tokens'/);
  assert.doesNotMatch(preview, /value:\s*'#[0-9A-Fa-f]{3,8}'/);
});

for (const component of registry.components.filter((entry) => entry.storyRequired)) {
  test(`${component.name} story renders the exact production export`, async () => {
    const story = await readFile(join(root, component.story), 'utf8');
    const localImport = new RegExp(`import \\{[^}]*\\b${component.name}\\b[^}]*\\} from '\\./${component.name}'`);
    const componentBinding = new RegExp(`component:\\s*${component.name}\\b`);
    assert.match(story, localImport);
    assert.match(story, componentBinding);
  });
}

test('Text default story compares the production body, label, and metadata roles', async () => {
  const story = await readFile(join(root, 'mobile/src/components/ui/Text.stories.tsx'), 'utf8');
  const defaultStory = story.slice(story.indexOf('export const Default:'), story.indexOf('export const TypeScale:'));
  assert.match(defaultStory, /role="body"/);
  assert.match(defaultStory, /role="label"/);
  assert.match(defaultStory, /role="metadata"/);
});

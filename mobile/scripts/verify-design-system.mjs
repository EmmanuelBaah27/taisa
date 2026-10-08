import { readFile, readdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const mobileRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const uiRoot = join(mobileRoot, 'src/components/ui');
const barrel = await readFile(join(uiRoot, 'index.ts'), 'utf8');
const sourceModules = [...barrel.matchAll(/export\s+(?:type\s+)?\{[^}]+\}\s+from\s+'\.\/(\w+)'/g)]
  .map((match) => match[1]);
const modules = [...new Set(sourceModules)];
const nativeOnlyModules = new Set(['RecordingGlow', 'CubeRefractionOverlay', 'GlowDevSheet']);
const files = new Set(await readdir(uiRoot));
const missingStories = modules.filter((moduleName) => (
  !nativeOnlyModules.has(moduleName) && !files.has(`${moduleName}.stories.tsx`)
));

if (missingStories.length > 0) {
  console.error(`Missing stories: ${missingStories.join(', ')}`);
  process.exit(1);
}

const designSystemDocs = await readFile(join(mobileRoot, '../docs/design-system.md'), 'utf8');
const undocumentedModules = modules.filter((moduleName) => !designSystemDocs.includes(`\`${moduleName}\``));

if (undocumentedModules.length > 0) {
  console.error(`Undocumented modules: ${undocumentedModules.join(', ')}`);
  process.exit(1);
}

const packageJson = JSON.parse(await readFile(join(mobileRoot, 'package.json'), 'utf8'));
if (packageJson.scripts?.['storybook:web'] !== 'EXPO_PUBLIC_STORYBOOK=true expo start --web') {
  console.error('storybook:web must start the on-demand browser catalog.');
  process.exit(1);
}

const entryPoint = await readFile(join(mobileRoot, 'index.ts'), 'utf8');
if (
  !entryPoint.includes("process.env.EXPO_PUBLIC_STORYBOOK === 'true'")
  || !entryPoint.includes("require('./.rnstorybook')")
  || !entryPoint.includes('registerRootComponent(StorybookUIRoot)')
  || !entryPoint.includes("require('expo-router/entry')")
) {
  console.error('index.ts must isolate the Storybook and Expo Router entry points.');
  process.exit(1);
}

const tailwindConfig = await readFile(join(mobileRoot, 'tailwind.config.js'), 'utf8');
if (!tailwindConfig.includes("darkMode: 'class'")) {
  console.error("Tailwind darkMode must be 'class' so Storybook backgrounds can control the browser canvas.");
  process.exit(1);
}

try {
  await readFile(join(mobileRoot, 'app/design-system.tsx'), 'utf8');
  console.error('The in-app design-system route must not exist.');
  process.exit(1);
} catch (error) {
  if (error?.code !== 'ENOENT') throw error;
}

const fontReferenceFiles = [
  'app/_layout.tsx',
  'global.css',
  'tailwind.config.js',
  '../docs/design-system.md',
];
for (const relativePath of fontReferenceFiles) {
  const contents = await readFile(join(mobileRoot, relativePath), 'utf8');
  if (contents.includes('Strichpunkt')) {
    console.error(`Strichpunkt reference remains: ${relativePath}`);
    process.exit(1);
  }
  for (const registration of ['Inter_400Regular', 'Inter_500Medium', 'Inter_600SemiBold', 'Inter_700Bold']) {
    if (!contents.includes(registration)) {
      console.error(`${registration} is missing from ${relativePath}`);
      process.exit(1);
    }
  }
}

console.log(`Design-system verification passed (${modules.length} catalog modules).`);

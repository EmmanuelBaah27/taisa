const { getDefaultConfig } = require('expo/metro-config');
const { withNativeWind } = require('nativewind/metro');
const { withStorybook } = require('@storybook/react-native/metro/withStorybook');
const path = require('path');

const projectRoot = __dirname;
const workspaceRoot = path.resolve(projectRoot, '..');

const config = getDefaultConfig(projectRoot);

// Watch the shared workspace package
config.watchFolders = [workspaceRoot];

// Resolve modules from mobile first, then workspace root
config.resolver.nodeModulesPaths = [
  path.resolve(projectRoot, 'node_modules'),
  path.resolve(workspaceRoot, 'node_modules'),
];

const isStorybook = process.env.EXPO_PUBLIC_STORYBOOK === 'true';

const nativewindConfig = withNativeWind(config, { input: './global.css' });

module.exports = isStorybook
  ? withStorybook(nativewindConfig, {
      enabled: true,
      configPath: path.resolve(__dirname, './.rnstorybook'),
    })
  : nativewindConfig;

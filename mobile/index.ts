if (process.env.EXPO_PUBLIC_STORYBOOK === 'true') {
  const { registerRootComponent } = require('expo');
  const StorybookUIRoot = require('./.rnstorybook').default;
  registerRootComponent(StorybookUIRoot);
} else {
  require('expo-router/entry');
}

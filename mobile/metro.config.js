const { getDefaultConfig } = require('expo/metro-config');
const { withNativeWind } = require('nativewind/metro');
const { withStorybook } = require('@storybook/react-native/metro/withStorybook');
const path = require('path');

const projectRoot = __dirname;
const workspaceRoot = path.resolve(projectRoot, '..');

const config = getDefaultConfig(projectRoot);

// Let physical devices using Expo's tunnel reach the local development API
// through the same HTTPS origin as Metro. This is development-only: production
// builds do not run Metro or this middleware.
config.server.enhanceMiddleware = (middleware) => (request, response, next) => {
  if (!request.url?.startsWith('/api/v1')) {
    return middleware(request, response, next);
  }

  const proxyRequest = require('http').request(
    {
      hostname: '127.0.0.1',
      port: 3000,
      path: request.url,
      method: request.method,
      headers: { ...request.headers, host: '127.0.0.1:3000' },
    },
    (proxyResponse) => {
      response.writeHead(proxyResponse.statusCode ?? 502, proxyResponse.headers);
      proxyResponse.pipe(response);
    },
  );

  proxyRequest.on('error', () => {
    if (!response.headersSent) {
      response.writeHead(502, { 'content-type': 'application/json' });
    }
    response.end(JSON.stringify({ error: 'Development API proxy unavailable' }));
  });

  request.pipe(proxyRequest);
};

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

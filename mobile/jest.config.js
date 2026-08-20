module.exports = {
  preset: 'jest-expo',
  roots: ['<rootDir>/src'],
  testMatch: ['**/__tests__/**/*.test.ts?(x)'],
  setupFiles: ['<rootDir>/src/repositories/__tests__/setupExpoCrypto.ts'],
};

import { readMobileApiConfig } from '../mobileApiConfig';

test('personal alpha accepts only a hosted HTTPS API origin', () => {
  expect(readMobileApiConfig({
    EXPO_PUBLIC_TAISA_BUILD_PROFILE: 'personal-alpha',
    EXPO_PUBLIC_API_URL: 'https://private-taisa.example/api/v1',
  })).toEqual({ baseUrl: 'https://private-taisa.example/api/v1' });
});

test.each([
  'http://localhost:3000/api/v1',
  'http://127.0.0.1:3000/api/v1',
  'http://192.168.1.4:3000/api/v1',
  'https://localhost/api/v1',
])('personal alpha rejects local or insecure API origin %s', (baseUrl) => {
  expect(() => readMobileApiConfig({
    EXPO_PUBLIC_TAISA_BUILD_PROFILE: 'personal-alpha',
    EXPO_PUBLIC_API_URL: baseUrl,
  })).toThrow('Personal alpha requires a hosted HTTPS API URL');
});

test('development retains an explicit local default without embedding secrets', () => {
  expect(readMobileApiConfig({})).toEqual({ baseUrl: 'http://localhost:3000/api/v1' });
});

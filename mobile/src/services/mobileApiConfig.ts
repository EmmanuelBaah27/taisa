type MobileEnvironment = Record<string, string | undefined>;

function isLocalHostname(hostname: string): boolean {
  const normalized = hostname.toLowerCase();
  if (normalized === 'localhost' || normalized === '::1' || normalized.endsWith('.local')) return true;
  if (/^127\./.test(normalized) || /^10\./.test(normalized) || /^192\.168\./.test(normalized)) return true;
  const match = normalized.match(/^172\.(\d+)\./);
  return match !== null && Number(match[1]) >= 16 && Number(match[1]) <= 31;
}

export function readMobileApiConfig(environment: MobileEnvironment): { baseUrl: string } {
  const profile = environment.EXPO_PUBLIC_TAISA_BUILD_PROFILE ?? 'development';
  const configured = environment.EXPO_PUBLIC_API_URL?.trim();
  const baseUrl = configured || 'http://localhost:3000/api/v1';
  if (profile === 'personal-alpha' || profile === 'production') {
    try {
      const url = new URL(baseUrl);
      if (
        url.protocol !== 'https:'
        || isLocalHostname(url.hostname)
        || !url.pathname.endsWith('/api/v1')
      ) throw new Error();
    } catch {
      throw new Error('Personal alpha requires a hosted HTTPS API URL');
    }
  }
  return { baseUrl: baseUrl.replace(/\/$/, '') };
}

export const mobileApiConfig = readMobileApiConfig({
  EXPO_PUBLIC_TAISA_BUILD_PROFILE: process.env.EXPO_PUBLIC_TAISA_BUILD_PROFILE,
  EXPO_PUBLIC_API_URL: process.env.EXPO_PUBLIC_API_URL,
});

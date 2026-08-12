import * as Crypto from 'expo-crypto';
import * as SecureStore from 'expo-secure-store';

const INSTALLATION_ID_KEY = 'taisa.installation-id.v1';
const SAFE_ID_PATTERN = /^[A-Za-z0-9._:-]{1,128}$/;

interface InstallationIdentityDependencies {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
  createId(): string;
}

export interface InstallationIdentity {
  get(): Promise<string>;
}

export function createInstallationIdentity(
  dependencies: InstallationIdentityDependencies,
): InstallationIdentity {
  let cached: string | null = null;
  let loading: Promise<string> | null = null;
  return {
    get() {
      if (cached !== null) return Promise.resolve(cached);
      if (loading !== null) return loading;
      const operation = (async () => {
        const stored = await dependencies.getItem(INSTALLATION_ID_KEY);
        if (stored !== null && SAFE_ID_PATTERN.test(stored)) {
          cached = stored;
          return stored;
        }
        const created = dependencies.createId();
        if (!SAFE_ID_PATTERN.test(created)) throw new Error('Installation identity is invalid');
        await dependencies.setItem(INSTALLATION_ID_KEY, created);
        cached = created;
        return created;
      })();
      loading = operation;
      void operation.then(
        () => { if (loading === operation) loading = null; },
        () => { if (loading === operation) loading = null; },
      );
      return operation;
    },
  };
}

const nativeInstallationIdentity = createInstallationIdentity({
  getItem: SecureStore.getItemAsync,
  async setItem(key, value) {
    await SecureStore.setItemAsync(key, value, {
      keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
    });
  },
  createId: Crypto.randomUUID,
});

export function getInstallationId(): Promise<string> {
  return nativeInstallationIdentity.get();
}

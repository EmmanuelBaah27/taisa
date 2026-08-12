import {
  DatabaseConfigurationRequiredError,
  DatabaseRecoveryRequiredError,
} from '../db/openDatabase';
import { LocalProfileArchiveError } from '../stores/careerStore';

export type StartupProfileResult =
  | { status: 'ready' }
  | { status: 'onboarding' }
  | {
    status: 'recovery-required';
    error: DatabaseRecoveryRequiredError | DatabaseConfigurationRequiredError;
  };

export async function hydrateStartupProfile(dependencies: {
  fetchProfile(): Promise<void>;
  route(path: '/onboarding'): void;
}): Promise<StartupProfileResult> {
  try {
    await dependencies.fetchProfile();
    return { status: 'ready' };
  } catch (error) {
    if (error instanceof LocalProfileArchiveError && error.reason === 'missing') {
      dependencies.route('/onboarding');
      return { status: 'onboarding' };
    }
    if (
      error instanceof DatabaseRecoveryRequiredError ||
      error instanceof DatabaseConfigurationRequiredError
    ) {
      return { status: 'recovery-required', error };
    }
    throw error;
  }
}

export function recoveryPresentation(
  error: DatabaseRecoveryRequiredError | DatabaseConfigurationRequiredError,
): { title: string; body: string } {
  if (error instanceof DatabaseConfigurationRequiredError) {
    return {
      title: 'Encrypted archive unavailable',
      body: 'This build cannot safely open your encrypted archive. Keep Taisa closed and retry after device storage and Keychain access are available.',
    };
  }
  return {
    title: 'Your archive needs recovery',
    body: 'Taisa cannot decrypt the archive with the key currently available on this phone. Your data has not been replaced. Restore Keychain access, then retry; an encrypted backup can be restored only when a usable device key is available.',
  };
}

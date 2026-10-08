import {
  DatabaseConfigurationRequiredError,
  DatabaseRecoveryRequiredError,
} from '../../db/openDatabase';
import { LocalProfileArchiveError } from '../../stores/careerStore';
import { hydrateStartupProfile } from '../startupProfile';

describe('startup profile routing', () => {
  test('reports an empty archive for routing only after the root navigator mounts', async () => {
    const fetchProfile = jest.fn(async () => {
      throw new LocalProfileArchiveError('missing');
    });
    await expect(hydrateStartupProfile({ fetchProfile })).resolves.toEqual({
      status: 'onboarding',
    });
  });

  test.each([
    new DatabaseRecoveryRequiredError('missing-key'),
    new DatabaseRecoveryRequiredError('invalid-key'),
    new DatabaseRecoveryRequiredError('key-store-unavailable'),
    new DatabaseRecoveryRequiredError('unreadable-database'),
    new DatabaseConfigurationRequiredError('secure-store-unavailable'),
    new DatabaseConfigurationRequiredError('sqlcipher-unavailable'),
  ])('surfaces encrypted archive failures without routing into readable screens', async (failure) => {
    await expect(hydrateStartupProfile({
      fetchProfile: async () => { throw failure; },
    })).resolves.toEqual({ status: 'recovery-required', error: failure });
  });
});

import {
  DatabaseConfigurationRequiredError,
  DatabaseRecoveryRequiredError,
} from '../../db/openDatabase';
import { LocalProfileArchiveError } from '../../stores/careerStore';
import { hydrateStartupProfile } from '../startupProfile';

describe('startup profile routing', () => {
  test('routes an empty archive to onboarding without creating a profile', async () => {
    const fetchProfile = jest.fn(async () => {
      throw new LocalProfileArchiveError('missing');
    });
    const route = jest.fn();

    await expect(hydrateStartupProfile({ fetchProfile, route })).resolves.toEqual({
      status: 'onboarding',
    });
    expect(route).toHaveBeenCalledWith('/onboarding');
  });

  test.each([
    new DatabaseRecoveryRequiredError('missing-key'),
    new DatabaseRecoveryRequiredError('invalid-key'),
    new DatabaseRecoveryRequiredError('key-store-unavailable'),
    new DatabaseRecoveryRequiredError('unreadable-database'),
    new DatabaseConfigurationRequiredError('secure-store-unavailable'),
    new DatabaseConfigurationRequiredError('sqlcipher-unavailable'),
  ])('surfaces encrypted archive failures without routing into readable screens', async (failure) => {
    const route = jest.fn();

    await expect(hydrateStartupProfile({
      fetchProfile: async () => { throw failure; },
      route,
    })).resolves.toEqual({ status: 'recovery-required', error: failure });
    expect(route).not.toHaveBeenCalled();
  });
});

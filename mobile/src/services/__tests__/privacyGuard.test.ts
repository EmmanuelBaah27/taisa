import {
  createPrivacyGuard,
  initialPrivacyGuardState,
  transitionPrivacyGuard,
} from '../privacyGuard';

describe('privacy guard state machine', () => {
  test('shields immediately when the app becomes inactive or backgrounded', () => {
    const unlocked = {
      ...initialPrivacyGuardState,
      initialized: true,
      lockEnabled: true,
      phase: 'unlocked' as const,
      appState: 'active' as const,
      shielded: false,
    };

    const inactive = transitionPrivacyGuard(unlocked, { type: 'app-state', value: 'inactive' });
    expect(inactive).toMatchObject({ phase: 'locked', shielded: true, appState: 'inactive' });

    const background = transitionPrivacyGuard(unlocked, { type: 'app-state', value: 'background' });
    expect(background).toMatchObject({ phase: 'locked', shielded: true, appState: 'background' });
  });

  test('keeps cancelled authentication locked and shielded', async () => {
    const guard = createPrivacyGuard({
      preference: {
        getEnabled: jest.fn(async () => true),
        setEnabled: jest.fn(async () => undefined),
      },
      authentication: {
        isAvailable: jest.fn(async () => true),
        authenticate: jest.fn(async () => false),
      },
    });

    await guard.initialize();
    await expect(guard.unlock()).resolves.toBe(false);
    expect(guard.getState()).toMatchObject({ phase: 'locked', shielded: true });
  });

  test('does not turn the Face ID system prompt into a new unlock attempt', () => {
    const unlocking = {
      ...initialPrivacyGuardState,
      initialized: true,
      lockEnabled: true,
      phase: 'unlocking' as const,
      appState: 'active' as const,
      shielded: true,
    };

    const inactive = transitionPrivacyGuard(unlocking, { type: 'app-state', value: 'inactive' });
    expect(inactive).toMatchObject({ phase: 'unlocking', shielded: true });

    const active = transitionPrivacyGuard(inactive, { type: 'app-state', value: 'active' });
    expect(active).toMatchObject({ phase: 'unlocking', shielded: true });
  });

  test('remembers Face ID success reported before iOS returns the app to active', () => {
    const promptInactive = {
      ...initialPrivacyGuardState,
      initialized: true,
      lockEnabled: true,
      phase: 'unlocking' as const,
      appState: 'inactive' as const,
      shielded: true,
    };

    const authenticated = transitionPrivacyGuard(promptInactive, { type: 'unlock-succeeded' });
    expect(authenticated).toMatchObject({ phase: 'unlocked', shielded: true });

    const active = transitionPrivacyGuard(authenticated, { type: 'app-state', value: 'active' });
    expect(active).toMatchObject({ phase: 'unlocked', shielded: false });
  });

  test('unshields only after successful authentication while active', async () => {
    const guard = createPrivacyGuard({
      preference: {
        getEnabled: jest.fn(async () => true),
        setEnabled: jest.fn(async () => undefined),
      },
      authentication: {
        isAvailable: jest.fn(async () => true),
        authenticate: jest.fn(async () => true),
      },
    });

    await guard.initialize();
    await expect(guard.unlock()).resolves.toBe(true);
    expect(guard.getState()).toMatchObject({ phase: 'unlocked', shielded: false });
  });

  test('does not enable app lock without enrolled device authentication', async () => {
    const setEnabled = jest.fn(async () => undefined);
    const guard = createPrivacyGuard({
      preference: { getEnabled: jest.fn(async () => false), setEnabled },
      authentication: {
        isAvailable: jest.fn(async () => false),
        authenticate: jest.fn(async () => true),
      },
    });

    await guard.initialize();
    await expect(guard.setLockEnabled(true)).rejects.toMatchObject({
      code: 'DEVICE_AUTHENTICATION_UNAVAILABLE',
    });
    expect(setEnabled).not.toHaveBeenCalled();
    expect(guard.getState()).toMatchObject({ lockEnabled: false, shielded: false });
  });

  test('stores only the boolean preference and never a biometric secret', async () => {
    const setEnabled = jest.fn(async () => undefined);
    const guard = createPrivacyGuard({
      preference: { getEnabled: jest.fn(async () => false), setEnabled },
      authentication: {
        isAvailable: jest.fn(async () => true),
        authenticate: jest.fn(async () => true),
      },
    });

    await guard.initialize();
    await guard.setLockEnabled(true);

    expect(setEnabled).toHaveBeenCalledWith(true);
    expect(setEnabled).toHaveBeenCalledTimes(1);
  });

  test('keeps the app shielded after returning active until unlock succeeds', () => {
    const background = {
      ...initialPrivacyGuardState,
      initialized: true,
      lockEnabled: true,
      phase: 'locked' as const,
      appState: 'background' as const,
      shielded: true,
    };

    expect(transitionPrivacyGuard(background, { type: 'app-state', value: 'active' }))
      .toMatchObject({ phase: 'locked', shielded: true, appState: 'active' });
  });

  test('fails closed when the lock preference cannot be read', async () => {
    const guard = createPrivacyGuard({
      preference: {
        getEnabled: jest.fn(async () => { throw new Error('keychain unavailable'); }),
        setEnabled: jest.fn(async () => undefined),
      },
      authentication: {
        isAvailable: jest.fn(async () => true),
        authenticate: jest.fn(async () => true),
      },
    });

    await expect(guard.initialize()).rejects.toMatchObject({
      code: 'PRIVACY_PREFERENCE_UNAVAILABLE',
    });
    expect(guard.getState()).toMatchObject({
      initialized: false,
      phase: 'initializing',
      shielded: true,
    });
  });
});

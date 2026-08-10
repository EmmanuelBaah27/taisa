import * as LocalAuthentication from 'expo-local-authentication';
import * as SecureStore from 'expo-secure-store';

export type GuardedAppState = 'active' | 'inactive' | 'background';
export type PrivacyGuardPhase = 'initializing' | 'locked' | 'unlocking' | 'unlocked';

export interface PrivacyGuardState {
  readonly initialized: boolean;
  readonly lockEnabled: boolean;
  readonly phase: PrivacyGuardPhase;
  readonly appState: GuardedAppState;
  readonly shielded: boolean;
}

export type PrivacyGuardEvent =
  | { readonly type: 'preference-loaded'; readonly enabled: boolean }
  | { readonly type: 'app-state'; readonly value: GuardedAppState }
  | { readonly type: 'unlock-started' }
  | { readonly type: 'unlock-succeeded' }
  | { readonly type: 'unlock-failed' }
  | { readonly type: 'lock-enabled'; readonly enabled: boolean };

export const initialPrivacyGuardState: PrivacyGuardState = {
  initialized: false,
  lockEnabled: false,
  phase: 'initializing',
  appState: 'active',
  // Fail closed during preference loading so private UI never flashes at startup.
  shielded: true,
};

export function transitionPrivacyGuard(
  state: PrivacyGuardState,
  event: PrivacyGuardEvent,
): PrivacyGuardState {
  switch (event.type) {
    case 'preference-loaded':
      return {
        ...state,
        initialized: true,
        lockEnabled: event.enabled,
        phase: event.enabled ? 'locked' : 'unlocked',
        shielded: event.enabled || state.appState !== 'active',
      };
    case 'app-state': {
      const isActive = event.value === 'active';
      return {
        ...state,
        appState: event.value,
        phase: !isActive && state.lockEnabled ? 'locked' : state.phase,
        shielded: !isActive || state.lockEnabled && state.phase !== 'unlocked',
      };
    }
    case 'unlock-started':
      if (!state.lockEnabled || state.appState !== 'active') return state;
      return { ...state, phase: 'unlocking', shielded: true };
    case 'unlock-succeeded':
      if (!state.lockEnabled || state.appState !== 'active') return state;
      return { ...state, phase: 'unlocked', shielded: false };
    case 'unlock-failed':
      return state.lockEnabled
        ? { ...state, phase: 'locked', shielded: true }
        : { ...state, phase: 'unlocked', shielded: state.appState !== 'active' };
    case 'lock-enabled':
      return {
        ...state,
        initialized: true,
        lockEnabled: event.enabled,
        phase: event.enabled ? 'locked' : 'unlocked',
        shielded: event.enabled || state.appState !== 'active',
      };
  }
}

interface PrivacyPreferenceBoundary {
  getEnabled(): Promise<boolean>;
  setEnabled(enabled: boolean): Promise<void>;
}

interface DeviceAuthenticationBoundary {
  isAvailable(): Promise<boolean>;
  authenticate(): Promise<boolean>;
}

export interface PrivacyGuardDependencies {
  readonly preference: PrivacyPreferenceBoundary;
  readonly authentication: DeviceAuthenticationBoundary;
}

export class PrivacyGuardError extends Error {
  constructor(readonly code: 'DEVICE_AUTHENTICATION_UNAVAILABLE' | 'PRIVACY_PREFERENCE_UNAVAILABLE') {
    super(code === 'DEVICE_AUTHENTICATION_UNAVAILABLE'
      ? 'Device authentication is not available or enrolled.'
      : 'The privacy preference could not be read securely.');
    this.name = 'PrivacyGuardError';
  }
}

export interface PrivacyGuard {
  getState(): PrivacyGuardState;
  subscribe(listener: (state: PrivacyGuardState) => void): () => void;
  initialize(): Promise<PrivacyGuardState>;
  handleAppState(value: GuardedAppState): PrivacyGuardState;
  unlock(): Promise<boolean>;
  setLockEnabled(enabled: boolean): Promise<void>;
}

export function createPrivacyGuard(dependencies: PrivacyGuardDependencies): PrivacyGuard {
  let state = initialPrivacyGuardState;
  const listeners = new Set<(state: PrivacyGuardState) => void>();
  let unlockInFlight: Promise<boolean> | null = null;

  function dispatch(event: PrivacyGuardEvent): PrivacyGuardState {
    state = transitionPrivacyGuard(state, event);
    for (const listener of listeners) listener(state);
    return state;
  }

  async function unlock(): Promise<boolean> {
    if (!state.lockEnabled) return true;
    if (state.appState !== 'active') return false;
    if (unlockInFlight !== null) return unlockInFlight;

    dispatch({ type: 'unlock-started' });
    const attempt = (async () => {
      let succeeded = false;
      try {
        succeeded = await dependencies.authentication.authenticate();
      } catch {
        succeeded = false;
      }
      dispatch({ type: succeeded ? 'unlock-succeeded' : 'unlock-failed' });
      return succeeded;
    })();
    unlockInFlight = attempt;
    try {
      return await attempt;
    } finally {
      if (unlockInFlight === attempt) unlockInFlight = null;
    }
  }

  return {
    getState: () => state,
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    async initialize() {
      let enabled: boolean;
      try {
        enabled = await dependencies.preference.getEnabled();
      } catch {
        throw new PrivacyGuardError('PRIVACY_PREFERENCE_UNAVAILABLE');
      }
      return dispatch({ type: 'preference-loaded', enabled });
    },
    handleAppState(value) {
      return dispatch({ type: 'app-state', value });
    },
    unlock,
    async setLockEnabled(enabled) {
      if (enabled && !(await dependencies.authentication.isAvailable())) {
        throw new PrivacyGuardError('DEVICE_AUTHENTICATION_UNAVAILABLE');
      }
      await dependencies.preference.setEnabled(enabled);
      dispatch({ type: 'lock-enabled', enabled });
    },
  };
}

const LOCK_PREFERENCE_KEY = 'taisa.app-lock.enabled.v1';

const nativePrivacyGuard = createPrivacyGuard({
  preference: {
    async getEnabled() {
      return await SecureStore.getItemAsync(LOCK_PREFERENCE_KEY) === '1';
    },
    async setEnabled(enabled) {
      await SecureStore.setItemAsync(LOCK_PREFERENCE_KEY, enabled ? '1' : '0', {
        keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
      });
    },
  },
  authentication: {
    async isAvailable() {
      return await LocalAuthentication.hasHardwareAsync()
        && await LocalAuthentication.isEnrolledAsync();
    },
    async authenticate() {
      const result = await LocalAuthentication.authenticateAsync({
        promptMessage: 'Unlock Taisa',
        cancelLabel: 'Cancel',
        fallbackLabel: 'Use Passcode',
      });
      return result.success;
    },
  },
});

export function getPrivacyGuard(): PrivacyGuard {
  return nativePrivacyGuard;
}

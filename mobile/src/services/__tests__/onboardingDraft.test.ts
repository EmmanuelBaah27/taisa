jest.mock('expo-secure-store', () => ({
  getItemAsync: jest.fn(),
  setItemAsync: jest.fn(),
  deleteItemAsync: jest.fn(),
}));

import * as SecureStore from 'expo-secure-store';
import {
  clearOnboardingDraft,
  loadOnboardingDraft,
  saveOnboardingDraft,
} from '../onboardingDraft';

const draft = {
  step: 1,
  form: {
    currentRole: 'Product designer',
    currentCompany: 'Private company',
    industry: 'Technology',
    yearsOfExperience: '8',
    careerStage: 'senior',
    shortTermGoal: 'Lead strategy work',
    longTermGoal: 'Grow into staff level',
    currentFocusArea: 'Influence',
    coachingStyle: 'direct',
    accountabilityLevel: 'moderate',
  },
};

describe('encrypted onboarding draft', () => {
  beforeEach(() => jest.clearAllMocks());

  test('saves and restores the local draft', async () => {
    (SecureStore.getItemAsync as jest.Mock).mockResolvedValue(JSON.stringify(draft));

    await saveOnboardingDraft(draft);
    await expect(loadOnboardingDraft()).resolves.toEqual(draft);

    expect(SecureStore.setItemAsync).toHaveBeenCalledWith(
      'taisa.onboarding-draft.v1',
      JSON.stringify(draft),
    );
  });

  test('ignores malformed stored data and clears only after success', async () => {
    (SecureStore.getItemAsync as jest.Mock).mockResolvedValue('{broken');
    await expect(loadOnboardingDraft()).resolves.toBeNull();

    await clearOnboardingDraft();
    expect(SecureStore.deleteItemAsync).toHaveBeenCalledWith('taisa.onboarding-draft.v1');
  });
});

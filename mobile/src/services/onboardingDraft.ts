import * as SecureStore from 'expo-secure-store';

const ONBOARDING_DRAFT_KEY = 'taisa.onboarding-draft.v1';

export interface OnboardingFormDraft {
  currentRole: string;
  currentCompany: string;
  industry: string;
  yearsOfExperience: string;
  careerStage: string;
  shortTermGoal: string;
  longTermGoal: string;
  currentFocusArea: string;
  coachingStyle: string;
  accountabilityLevel: string;
}

export interface OnboardingDraft {
  step: number;
  form: OnboardingFormDraft;
}

let writeTail = Promise.resolve();

function isStringRecord(value: unknown, keys: readonly string[]): value is Record<string, string> {
  return Boolean(
    value
    && typeof value === 'object'
    && keys.every((key) => typeof (value as Record<string, unknown>)[key] === 'string'),
  );
}

export async function loadOnboardingDraft(): Promise<OnboardingDraft | null> {
  const serialized = await SecureStore.getItemAsync(ONBOARDING_DRAFT_KEY);
  if (!serialized) return null;
  try {
    const value = JSON.parse(serialized) as unknown;
    if (!value || typeof value !== 'object') return null;
    const candidate = value as { step?: unknown; form?: unknown };
    const keys = [
      'currentRole', 'currentCompany', 'industry', 'yearsOfExperience', 'careerStage',
      'shortTermGoal', 'longTermGoal', 'currentFocusArea', 'coachingStyle',
      'accountabilityLevel',
    ] as const;
    if (
      typeof candidate.step !== 'number'
      || candidate.step < 0
      || candidate.step > 2
      || !isStringRecord(candidate.form, keys)
    ) return null;
    return candidate as OnboardingDraft;
  } catch {
    return null;
  }
}

export function saveOnboardingDraft(draft: OnboardingDraft): Promise<void> {
  const serialized = JSON.stringify(draft);
  const operation = writeTail.then(() => SecureStore.setItemAsync(ONBOARDING_DRAFT_KEY, serialized));
  writeTail = operation.catch(() => undefined);
  return operation;
}

export function clearOnboardingDraft(): Promise<void> {
  const operation = writeTail.then(() => SecureStore.deleteItemAsync(ONBOARDING_DRAFT_KEY));
  writeTail = operation.catch(() => undefined);
  return operation;
}

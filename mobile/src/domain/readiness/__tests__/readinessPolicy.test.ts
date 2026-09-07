import type { CapabilitySnapshot, ReadinessPolicy } from '@taisa/shared';

import {
  evaluateReadiness,
  grantAuthority,
  recordOperationOutcome,
  reconcileCapability,
  revokeAuthority,
} from '../readinessPolicy';

const policy: ReadinessPolicy = {
  operation: 'complete_explicit_task',
  version: 1,
  minimumRelevantExamples: 8,
  maximumEvidenceAgeDays: 30,
  maximumCorrections: 1,
  trialSampleSize: 5,
  contradictionsAllowed: 0,
};

function snapshot(overrides: Partial<CapabilitySnapshot> = {}): CapabilitySnapshot {
  return {
    operation: policy.operation,
    policyVersion: 1,
    state: 'learning',
    permissionGrantedAt: null,
    relevantExamples: 0,
    corrections: 0,
    contradictions: 0,
    latestEvidenceAt: null,
    cleanTrialOutcomes: 0,
    updatedAt: '2026-08-25T08:00:00Z',
    ...overrides,
  };
}

const now = '2026-08-26T08:00:00Z';

test('qualifying evidence reaches Ready but never grants authority', () => {
  const result = evaluateReadiness(policy, snapshot({
    relevantExamples: 8,
    latestEvidenceAt: '2026-08-25T08:00:00Z',
  }), now);

  expect(result.state).toBe('ready');
  expect(result.permissionGrantedAt).toBeNull();
});

test('only the user can move Ready to Permission granted', () => {
  const result = grantAuthority(snapshot({ state: 'ready' }), now);

  expect(result.state).toBe('permission_granted');
  expect(result.permissionGrantedAt).toBe(now);
});

test('Trial becomes Trusted only after the configured clean sample', () => {
  expect(reconcileCapability(policy, snapshot({
    state: 'trial', permissionGrantedAt: '2026-08-24T08:00:00Z',
    relevantExamples: 8, latestEvidenceAt: now, cleanTrialOutcomes: 4,
  }), now).state).toBe('trial');

  expect(reconcileCapability(policy, snapshot({
    state: 'trial', permissionGrantedAt: '2026-08-24T08:00:00Z',
    relevantExamples: 8, latestEvidenceAt: now, cleanTrialOutcomes: 5,
  }), now).state).toBe('trusted');
});

test('stale or contradictory evidence returns delegated capability to Ask me', () => {
  expect(reconcileCapability(policy, snapshot({
    state: 'trusted', permissionGrantedAt: '2026-08-24T08:00:00Z',
    relevantExamples: 8, latestEvidenceAt: '2026-06-01T08:00:00Z',
    cleanTrialOutcomes: 5,
  }), now).state).toBe('ask_me');

  expect(reconcileCapability(policy, snapshot({
    state: 'trusted', permissionGrantedAt: '2026-08-24T08:00:00Z',
    relevantExamples: 8, latestEvidenceAt: now, contradictions: 1,
    cleanTrialOutcomes: 5,
  }), now).state).toBe('ask_me');
});

test('policy version change removes permission and relearns independently', () => {
  const result = reconcileCapability({ ...policy, version: 2 }, snapshot({
    state: 'trusted', permissionGrantedAt: '2026-08-24T08:00:00Z',
    relevantExamples: 8, latestEvidenceAt: now, cleanTrialOutcomes: 5,
  }), now);

  expect(result).toMatchObject({
    state: 'learning', policyVersion: 2, permissionGrantedAt: null,
  });
});

test('success, correction, and contradiction update only explicit evidence dimensions', () => {
  const trial = snapshot({
    state: 'trial', permissionGrantedAt: '2026-08-24T08:00:00Z',
    relevantExamples: 8, latestEvidenceAt: now,
  });

  expect(recordOperationOutcome(trial, 'success', now)).toMatchObject({
    relevantExamples: 9, cleanTrialOutcomes: 1, corrections: 0, contradictions: 0,
  });
  expect(recordOperationOutcome(trial, 'correction', now)).toMatchObject({
    relevantExamples: 9, cleanTrialOutcomes: 0, corrections: 1, contradictions: 0,
  });
  expect(recordOperationOutcome(trial, 'contradiction', now)).toMatchObject({
    relevantExamples: 9, cleanTrialOutcomes: 0, corrections: 0, contradictions: 1,
  });
});

test('manual revocation immediately returns one delegated capability to Ask me', () => {
  const result = revokeAuthority(snapshot({
    state: 'trusted', permissionGrantedAt: '2026-08-24T08:00:00Z',
    relevantExamples: 8, latestEvidenceAt: now, cleanTrialOutcomes: 5,
  }), now);

  expect(result).toMatchObject({
    operation: 'complete_explicit_task', state: 'ask_me', permissionGrantedAt: null,
  });
});

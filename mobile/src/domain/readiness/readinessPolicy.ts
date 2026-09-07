import type { CapabilitySnapshot, ReadinessPolicy } from '@taisa/shared';

export class ReadinessError extends Error {
  constructor(readonly code: 'NOT_READY' | 'INVALID_TIMESTAMP') {
    super(code);
    this.name = 'ReadinessError';
  }
}

function evidenceAgeDays(latestEvidenceAt: string | null, now: string): number {
  if (latestEvidenceAt === null) return Number.POSITIVE_INFINITY;
  const latestMs = Date.parse(latestEvidenceAt);
  const nowMs = Date.parse(now);
  if (!Number.isFinite(latestMs) || !Number.isFinite(nowMs) || latestMs > nowMs) {
    throw new ReadinessError('INVALID_TIMESTAMP');
  }
  return (nowMs - latestMs) / 86_400_000;
}

function qualifies(
  policy: ReadinessPolicy,
  snapshot: CapabilitySnapshot,
  now: string,
): boolean {
  return snapshot.relevantExamples >= policy.minimumRelevantExamples
    && snapshot.corrections <= policy.maximumCorrections
    && snapshot.contradictions <= policy.contradictionsAllowed
    && evidenceAgeDays(snapshot.latestEvidenceAt, now) <= policy.maximumEvidenceAgeDays;
}

export function evaluateReadiness(
  policy: ReadinessPolicy,
  snapshot: CapabilitySnapshot,
  now: string,
): CapabilitySnapshot {
  const state = qualifies(policy, snapshot, now) ? 'ready' : 'learning';
  return {
    ...snapshot,
    policyVersion: policy.version,
    state,
    permissionGrantedAt: null,
    updatedAt: now,
  };
}

export function grantAuthority(
  snapshot: CapabilitySnapshot,
  now: string,
): CapabilitySnapshot {
  if (snapshot.state !== 'ready') throw new ReadinessError('NOT_READY');
  return {
    ...snapshot,
    state: 'permission_granted',
    permissionGrantedAt: now,
    updatedAt: now,
  };
}

export type OperationOutcome = 'success' | 'correction' | 'contradiction';

export function recordOperationOutcome(
  snapshot: CapabilitySnapshot,
  outcome: OperationOutcome,
  now: string,
): CapabilitySnapshot {
  return {
    ...snapshot,
    relevantExamples: snapshot.relevantExamples + 1,
    corrections: snapshot.corrections + (outcome === 'correction' ? 1 : 0),
    contradictions: snapshot.contradictions + (outcome === 'contradiction' ? 1 : 0),
    cleanTrialOutcomes: outcome === 'success' && snapshot.state === 'trial'
      ? snapshot.cleanTrialOutcomes + 1
      : 0,
    latestEvidenceAt: now,
    updatedAt: now,
  };
}

export function revokeAuthority(
  snapshot: CapabilitySnapshot,
  now: string,
): CapabilitySnapshot {
  return {
    ...snapshot,
    state: 'ask_me',
    permissionGrantedAt: null,
    cleanTrialOutcomes: 0,
    updatedAt: now,
  };
}

export function reconcileCapability(
  policy: ReadinessPolicy,
  snapshot: CapabilitySnapshot,
  now: string,
): CapabilitySnapshot {
  if (snapshot.policyVersion !== policy.version) {
    return {
      ...snapshot,
      policyVersion: policy.version,
      state: 'learning',
      permissionGrantedAt: null,
      cleanTrialOutcomes: 0,
      updatedAt: now,
    };
  }

  if (!qualifies(policy, snapshot, now)) {
    const hadAuthority = ['permission_granted', 'trial', 'trusted'].includes(snapshot.state);
    return {
      ...snapshot,
      state: hadAuthority ? 'ask_me' : 'learning',
      permissionGrantedAt: null,
      cleanTrialOutcomes: 0,
      updatedAt: now,
    };
  }

  let state = snapshot.state;
  if (state === 'learning' || state === 'ask_me') state = 'ready';
  else if (state === 'permission_granted') state = 'trial';
  else if (state === 'trial' && snapshot.cleanTrialOutcomes >= policy.trialSampleSize) {
    state = 'trusted';
  }
  return { ...snapshot, state, updatedAt: now };
}

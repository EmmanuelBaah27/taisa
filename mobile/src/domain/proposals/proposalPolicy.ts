import type { ProposalEnvelope, ProposalType } from '@taisa/shared';

export type ProposalAdmission<T extends ProposalType> =
  | { kind: 'admitted'; proposal: ProposalEnvelope<T> }
  | { kind: 'consolidated'; proposal: ProposalEnvelope<T> }
  | { kind: 'suppressed'; reason: 'rejected_same_evidence' };

function sameEffect<T extends ProposalType>(
  left: ProposalEnvelope<T>,
  right: ProposalEnvelope<T>,
): boolean {
  return JSON.stringify(left.effect) === JSON.stringify(right.effect);
}

export function admitProposal<T extends ProposalType>(
  incoming: ProposalEnvelope<T>,
  existing: readonly ProposalEnvelope<T>[],
): ProposalAdmission<T> {
  const match = existing.find((candidate) =>
    candidate.type === incoming.type
    && candidate.evidenceFingerprint === incoming.evidenceFingerprint
    && sameEffect(candidate, incoming),
  );

  if (match?.resolution === 'rejected') {
    return { kind: 'suppressed', reason: 'rejected_same_evidence' };
  }
  if (match) {
    return {
      kind: 'consolidated',
      proposal: {
        ...match,
        evidenceIds: [...new Set([...match.evidenceIds, ...incoming.evidenceIds])],
      },
    };
  }
  return { kind: 'admitted', proposal: { ...incoming, admission: 'admitted' } };
}

export function eligibleConfirmAll<T extends ProposalType>(
  proposals: readonly ProposalEnvelope<T>[],
): ProposalEnvelope<T>[] {
  return proposals.filter((proposal) =>
    proposal.ambiguity === 'strong'
    && proposal.admission === 'admitted'
    && proposal.resolution === 'unapplied'
    && proposal.revalidation === 'valid',
  );
}

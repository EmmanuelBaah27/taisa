import type { ProposalEnvelope } from '@taisa/shared';

import { admitProposal, eligibleConfirmAll } from '../proposalPolicy';

function proposal(
  overrides: Partial<ProposalEnvelope<'project_association'>> = {},
): ProposalEnvelope<'project_association'> {
  return {
    id: 'proposal-1', type: 'project_association', sourceId: 'conversation-1',
    sourceRevision: 2, evidenceIds: ['evidence-1'], evidenceFingerprint: 'fp-1',
    reasoning: 'Explicit project name', effect: { recordId: 'task-1', projectId: 'project-1' },
    ambiguity: 'strong', admission: 'admitted', resolution: 'unapplied',
    revalidation: 'valid', createdAt: '2026-08-25T08:00:00Z',
    updatedAt: '2026-08-25T08:00:00Z', ...overrides,
  };
}

test('same fingerprint and effect consolidates evidence instead of duplicating review', () => {
  const existing = proposal();
  const incoming = proposal({ id: 'proposal-2', evidenceIds: ['evidence-2'] });

  expect(admitProposal(incoming, [existing])).toEqual({
    kind: 'consolidated',
    proposal: { ...existing, evidenceIds: ['evidence-1', 'evidence-2'] },
  });
});

test('rejected identical evidence is suppressed', () => {
  const rejected = proposal({ resolution: 'rejected' });

  expect(admitProposal(proposal({ id: 'proposal-2' }), [rejected])).toEqual({
    kind: 'suppressed',
    reason: 'rejected_same_evidence',
  });
});

test('Confirm all includes only strong admitted valid unapplied proposals', () => {
  const strong = proposal();
  const ambiguous = proposal({ id: 'proposal-2', ambiguity: 'ambiguous' });
  const stale = proposal({ id: 'proposal-3', revalidation: 'stale' });
  const pending = proposal({ id: 'proposal-4', admission: 'pending' });

  expect(eligibleConfirmAll([strong, ambiguous, stale, pending]).map((item) => item.id))
    .toEqual(['proposal-1']);
});

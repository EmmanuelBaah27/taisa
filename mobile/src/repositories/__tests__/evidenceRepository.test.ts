import type { LocalEvidenceItem } from '@taisa/shared';

import {
  getEvidence,
  insertEvidence,
  listEvidence,
  searchEvidence,
  updateEvidence,
} from '../evidenceRepository';
import { createTestDatabase, LATER, NOW } from './testDatabase';

const evidence: LocalEvidenceItem = {
  id: 'evidence-1',
  statement: 'Led the roadmap workshop and aligned three stakeholders.',
  occurredAt: NOW,
  sourceMessageIds: ['message-source-1'],
  goalIds: ['goal-1'],
  actionIds: ['action-1'],
  createdAt: NOW,
  updatedAt: NOW,
};

describe('evidenceRepository', () => {
  test('creates, reads, updates, lists, searches, and preserves source traceability', async () => {
    const db = createTestDatabase();

    try {
      await db.withTransaction((tx) => insertEvidence(tx, evidence, 'evidence-create-1'));
      expect(await getEvidence(db, evidence.id)).toEqual(evidence);
      expect(await listEvidence(db)).toEqual([evidence]);
      expect(await searchEvidence(db, 'stakeholders')).toEqual([evidence]);

      const updated: LocalEvidenceItem = {
        ...evidence,
        statement: 'Led a roadmap workshop and aligned product stakeholders.',
        sourceMessageIds: ['message-source-1', 'message-source-2'],
        updatedAt: LATER,
      };
      await db.withTransaction((tx) => updateEvidence(tx, updated, 'evidence-update-1'));
      expect(await getEvidence(db, evidence.id)).toEqual(updated);
      expect(await searchEvidence(db, 'product')).toEqual([updated]);
    } finally {
      db.close();
    }
  });
});

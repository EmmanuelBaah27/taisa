import type { Experiment, GrowthReflection, Insight } from '@taisa/shared';

import type { RepositoryConnection, RepositoryTransaction } from '../db/types';

export interface InsightRepository {
  insertInsight(transaction: RepositoryTransaction, insight: Insight): Promise<void>;
  insertReflection(transaction: RepositoryTransaction, reflection: GrowthReflection): Promise<void>;
  insertExperiment(transaction: RepositoryTransaction, experiment: Experiment): Promise<void>;
}

export function createInsightRepository(_database: RepositoryConnection): InsightRepository {
  return {
    async insertInsight(transaction, insight) {
      await transaction.runAsync(
        `INSERT INTO insights
          (id, kind, title, body, freshness, evidence_json, created_at, updated_at)
         VALUES ($id, $kind, $title, $body, $freshness, $evidenceJson, $createdAt, $updatedAt)`,
        {
          $id: insight.id, $kind: insight.kind, $title: insight.title, $body: insight.body,
          $freshness: insight.freshness, $evidenceJson: JSON.stringify(insight.evidence),
          $createdAt: insight.createdAt, $updatedAt: insight.updatedAt,
        },
      );
    },
    async insertReflection(transaction, reflection) {
      await transaction.runAsync(
        `INSERT INTO growth_reflections
          (id, title, body, state, evidence_json, created_at, updated_at)
         VALUES ($id, $title, $body, $state, $evidenceJson, $createdAt, $updatedAt)`,
        {
          $id: reflection.id, $title: reflection.title, $body: reflection.body,
          $state: reflection.state, $evidenceJson: JSON.stringify(reflection.evidence),
          $createdAt: reflection.createdAt, $updatedAt: reflection.updatedAt,
        },
      );
    },
    async insertExperiment(transaction, experiment) {
      await transaction.runAsync(
        `INSERT INTO experiments
          (id, title, hypothesis, state, source_reflection_id, created_at, updated_at)
         VALUES ($id, $title, $hypothesis, $state, $sourceReflectionId, $createdAt, $updatedAt)`,
        {
          $id: experiment.id, $title: experiment.title, $hypothesis: experiment.hypothesis,
          $state: experiment.state, $sourceReflectionId: experiment.sourceReflectionId,
          $createdAt: experiment.createdAt, $updatedAt: experiment.updatedAt,
        },
      );
    },
  };
}

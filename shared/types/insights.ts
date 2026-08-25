export interface EvidenceLink {
  evidenceId: string;
  sourceId: string;
  sourceRevision: number;
}

export interface Insight {
  id: string;
  kind: 'operational';
  title: string;
  body: string;
  freshness: 'current' | 'stale' | 'contradictory';
  evidence: EvidenceLink[];
  createdAt: string;
  updatedAt: string;
}

export interface GrowthReflection {
  id: string;
  kind: 'growth_reflection';
  title: string;
  body: string;
  state: 'proposed' | 'confirmed' | 'rejected';
  evidence: EvidenceLink[];
  createdAt: string;
  updatedAt: string;
}

export interface Experiment {
  id: string;
  title: string;
  hypothesis: string;
  state: 'proposed' | 'active' | 'completed' | 'abandoned';
  sourceReflectionId: string | null;
  createdAt: string;
  updatedAt: string;
}

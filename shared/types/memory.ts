export type MemoryType =
  | 'goal'
  | 'commitment'
  | 'decision'
  | 'preference'
  | 'career_context'
  | 'development_area'
  | 'evidence'
  | 'pattern';

export type MemoryProvenance =
  | 'user-stated'
  | 'user-confirmed'
  | 'ai-inferred'
  | 'system-observed';

export type MemoryLifecycle =
  | 'proposed'
  | 'active'
  | 'paused'
  | 'superseded'
  | 'completed'
  | 'rejected'
  | 'archived';

export type MemoryConfidence = 'tentative' | 'supported' | 'established';

export interface MemoryItem {
  id: string;
  type: MemoryType;
  statement: string;
  provenance: MemoryProvenance;
  lifecycle: MemoryLifecycle;
  confidence: MemoryConfidence;
  createdAt: string;
  confirmedAt: string | null;
  lastSupportedAt: string;
  statusChangedAt: string;
  sourceMessageIds: string[];
  supersedesId?: string | null;
}

export type MemoryDelta =
  | {
      operation: 'propose';
      candidate: Omit<MemoryItem, 'id' | 'createdAt' | 'confirmedAt' | 'lastSupportedAt' | 'statusChangedAt'>;
      reason: string;
      requiresConfirmation: boolean;
    }
  | {
      operation: 'transition';
      targetId: string;
      to: MemoryLifecycle;
      reason: string;
      requiresConfirmation: boolean;
    }
  | {
      operation: 'support';
      targetId: string;
      sourceMessageId: string;
      reason: string;
      requiresConfirmation: false;
    };

export interface EvidenceItem {
  id: string;
  statement: string;
  occurredAt: string;
  sourceMessageIds: string[];
  goalIds: string[];
  actionIds: string[];
}

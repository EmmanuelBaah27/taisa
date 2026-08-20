import type { EvidenceItem } from '@taisa/shared';

export interface EvidenceRankingQuery {
  text: string;
  directEvidenceIds: readonly string[];
  directSourceMessageIds: readonly string[];
  goalIds: readonly string[];
  actionIds: readonly string[];
}

interface RankedEvidence<T extends EvidenceItem> {
  item: T;
  direct: number;
  shared: number;
  occurredAt: number;
  relevance: number;
}

function stableCompare(left: string, right: string): number {
  if (left < right) return -1;
  if (left > right) return 1;
  return 0;
}

function tokens(value: string): Set<string> {
  return new Set(
    value
      .normalize('NFKD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase()
      .split(/[^\p{L}\p{N}]+/u)
      .filter((token) => token.length > 0),
  );
}

function intersectionSize(left: readonly string[], right: Set<string>): number {
  return new Set(left.filter((value) => right.has(value))).size;
}

function timestampValue(value: string): number {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2})$/.test(value)) {
    return Number.NEGATIVE_INFINITY;
  }
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : Number.NEGATIVE_INFINITY;
}

export function rankEvidence<T extends EvidenceItem>(
  query: EvidenceRankingQuery,
  candidates: readonly T[],
): T[] {
  const directEvidenceIds = new Set(query.directEvidenceIds);
  const directSourceMessageIds = new Set(query.directSourceMessageIds);
  const goalIds = new Set(query.goalIds);
  const actionIds = new Set(query.actionIds);
  const queryTokens = tokens(query.text);

  const ranked: RankedEvidence<T>[] = candidates.map((item) => {
    const direct = Number(
      directEvidenceIds.has(item.id) ||
        item.sourceMessageIds.some((id) => directSourceMessageIds.has(id)),
    );
    const shared =
      intersectionSize(item.goalIds, goalIds) + intersectionSize(item.actionIds, actionIds);
    const relevance = intersectionSize([...tokens(item.statement)], queryTokens);
    return {
      item,
      direct,
      shared,
      occurredAt: timestampValue(item.occurredAt),
      relevance,
    };
  });

  return ranked
    .filter((candidate) => candidate.direct > 0 || candidate.shared > 0 || candidate.relevance > 0)
    .sort(
      (left, right) =>
        right.direct - left.direct ||
        right.shared - left.shared ||
        right.occurredAt - left.occurredAt ||
        right.relevance - left.relevance ||
        stableCompare(left.item.id, right.item.id),
    )
    .map((candidate) => candidate.item);
}

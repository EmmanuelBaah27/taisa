import type { HomeSectionKind, HomeView, Insight, WeeklyPeriod, WorkRecord } from '@taisa/shared';

export interface HomeSelectionInput {
  period: WeeklyPeriod;
  records: readonly WorkRecord[];
  insights: readonly Insight[];
  pendingProposalCount: number;
}

const SECTION_ORDER: readonly HomeSectionKind[] = [
  'lead_insight',
  'this_week',
  'carry_over',
  'updates_to_review',
  'weekly_review',
  'organize_week',
  'keep_moving',
  'conversation_input',
];

function newestFirst<T extends { id: string; updatedAt: string }>(left: T, right: T): number {
  return right.updatedAt.localeCompare(left.updatedAt) || left.id.localeCompare(right.id);
}

export function selectHome(input: HomeSelectionInput): HomeView {
  const uniqueRecords = [...new Map(input.records.map((record) => [record.id, record])).values()];
  const actionable = uniqueRecords.filter((record) =>
    !['completed', 'resolved', 'cancelled'].includes(record.status)
    && record.freshness !== 'contradictory',
  );
  const thisWeek = actionable
    .filter((record) => record.plannedWeek === input.period.startsOn)
    .sort(newestFirst);
  const carryOver = actionable
    .filter((record) => record.plannedWeek !== null && record.plannedWeek < input.period.startsOn)
    .sort(newestFirst);
  const shown = new Set([...thisWeek, ...carryOver].map((record) => record.id));
  const keepMoving = actionable
    .filter((record) => !shown.has(record.id) && record.plannedWeek === null)
    .sort(newestFirst)
    .slice(0, 3);
  const leadInsight = input.insights
    .filter((candidate) => candidate.freshness === 'current')
    .sort(newestFirst)[0] ?? null;

  const itemIds: Partial<Record<HomeSectionKind, string[]>> = {
    lead_insight: leadInsight === null ? [] : [leadInsight.id],
    this_week: thisWeek.map((record) => record.id),
    carry_over: carryOver.map((record) => record.id),
    updates_to_review: [],
    weekly_review: [input.period.id],
    organize_week: [],
    keep_moving: keepMoving.map((record) => record.id),
    conversation_input: [],
  };
  return {
    period: input.period,
    sections: SECTION_ORDER.map((kind) => ({ kind, itemIds: itemIds[kind] ?? [] })),
    leadInsight,
    thisWeek,
    carryOver,
    keepMoving,
    pendingProposalCount: input.pendingProposalCount,
  };
}

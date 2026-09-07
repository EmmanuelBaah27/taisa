export type BehaviorCategory = 'correction' | 'confirmation' | 'timing' | 'navigation';

export interface BehavioralEvent {
  id: string;
  category: BehaviorCategory;
  eventType: string;
  occurredAt: string;
  expiresAt: string;
}

export function reconcileBehaviorEvents(
  events: readonly BehavioralEvent[],
  options: { now: string; pausedCategories: ReadonlySet<BehaviorCategory> },
): { retained: BehavioralEvent[]; deleteIds: string[] } {
  const retained: BehavioralEvent[] = [];
  const deleteIds: string[] = [];
  for (const event of events) {
    if (event.expiresAt <= options.now) deleteIds.push(event.id);
    else if (!options.pausedCategories.has(event.category)) retained.push(event);
  }
  return { retained, deleteIds };
}

export function selectBehaviorDeletion(
  events: readonly BehavioralEvent[],
  category: BehaviorCategory | 'all',
): string[] {
  return events
    .filter((event) => category === 'all' || event.category === category)
    .map((event) => event.id);
}

export interface BehaviorPreviewPeriod {
  startsAt: string;
  endsAt: string;
}

export function buildBehaviorSubmissionPreview(
  events: readonly BehavioralEvent[],
  period: BehaviorPreviewPeriod,
): {
  period: BehaviorPreviewPeriod;
  categories: Array<{ category: BehaviorCategory; count: number }>;
} {
  const counts = new Map<BehaviorCategory, number>();
  for (const event of events) {
    if (event.occurredAt < period.startsAt || event.occurredAt > period.endsAt) continue;
    counts.set(event.category, (counts.get(event.category) ?? 0) + 1);
  }
  return {
    period,
    categories: [...counts.entries()]
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([category, count]) => ({ category, count })),
  };
}

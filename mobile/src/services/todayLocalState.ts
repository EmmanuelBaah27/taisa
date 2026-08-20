export type LocalTodayState =
  | { kind: 'empty'; title: string; body: string }
  | { kind: 'resume'; conversationId: string; title: string };

export function localTodayState(
  conversations: ReadonlyArray<{ id: string; title: string }>,
): LocalTodayState {
  const newest = conversations[0];
  if (newest === undefined) {
    return {
      kind: 'empty',
      title: 'Start with a work moment',
      body: 'Capture a thought privately or submit it when you want Taisa to coach with you.',
    };
  }
  return { kind: 'resume', conversationId: newest.id, title: newest.title };
}

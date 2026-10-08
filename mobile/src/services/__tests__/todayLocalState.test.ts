import { localTodayState } from '../todayLocalState';

describe('local Today state', () => {
  test('shows an explicit local empty state without requiring a server feed', () => {
    expect(localTodayState([])).toEqual({
      kind: 'empty',
      title: 'Start with a work moment',
      body: 'Capture a thought privately or submit it when you want Taisa to coach with you.',
    });
  });

  test('uses the newest local conversation as the return point', () => {
    expect(localTodayState([{ id: 'conversation-1', title: 'Stakeholder follow-up' }])).toEqual({
      kind: 'resume',
      conversationId: 'conversation-1',
      title: 'Stakeholder follow-up',
    });
  });
});

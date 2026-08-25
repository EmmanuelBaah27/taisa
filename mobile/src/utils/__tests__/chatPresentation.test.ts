import {
  getChatPreview,
  getChatTitle,
  groupChatsByDate,
  isVisibleChatSummary,
  type ChatSummary,
} from '../chatPresentation';

const summaries: ChatSummary[] = [
  {
    id: 'older',
    title: 'Older',
    updatedAt: '2026-08-13T08:00:00Z',
    lastUserMessage: 'User note',
    lastAssistantMessage: 'Coach note',
  },
  {
    id: 'newer',
    title: 'Newer',
    updatedAt: '2026-08-13T16:00:00Z',
    lastUserMessage: null,
    lastAssistantMessage: 'Coach only',
  },
  {
    id: 'past',
    title: null,
    updatedAt: '2026-08-11T12:00:00Z',
    lastUserMessage: null,
    lastAssistantMessage: null,
  },
];

describe('chat presentation', () => {
  test('groups chats by local calendar day and sorts newest first', () => {
    const groups = groupChatsByDate(summaries, new Date('2026-08-13T20:00:00Z'));

    expect(groups.map((group) => group.label)).toEqual([
      'Today, 13 Aug 2026',
    ]);
    expect(groups[0].chats.map((chat) => chat.id)).toEqual(['newer', 'older']);
  });

  test('prefers the latest user preview and degrades gracefully', () => {
    expect(getChatPreview(summaries[0])).toBe('User note');
    expect(getChatPreview(summaries[1])).toBe('Coach only');
    expect(getChatPreview(summaries[2])).toBe('Open conversation');
  });

  test('shows the actual latest message regardless of sender when supplied', () => {
    expect(getChatPreview({ ...summaries[0], lastMessage: 'Newest assistant reply' }))
      .toBe('Newest assistant reply');
  });

  test('replaces generic voice-reflection titles with a concise conversation topic', () => {
    expect(getChatTitle({
      ...summaries[0],
      title: 'Voice reflection',
      lastUserMessage: 'Preparing for the stakeholder review and clarifying the decision',
    })).toBe('Preparing for the stakeholder review and clarifying…');
    expect(getChatTitle(summaries[0])).toBe('Older');
  });

  test('presents a retained failed transcription as a recoverable recording row', () => {
    const failed: ChatSummary = {
      ...summaries[2],
      recoveryState: 'transcription-failed-recording-available',
    };

    expect(getChatTitle(failed)).toBe('Transcription failed');
    expect(getChatPreview(failed)).toBe('Recording saved · Tap to retry');
    expect(isVisibleChatSummary(failed)).toBe(true);
    expect(isVisibleChatSummary(summaries[2])).toBe(false);
  });
});

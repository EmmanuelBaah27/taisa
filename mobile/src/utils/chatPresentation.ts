import { format, isSameDay } from 'date-fns';

import type { ChatSummary } from '../repositories/conversationRepository';

export type { ChatSummary } from '../repositories/conversationRepository';

export interface ChatDateGroup {
  key: string;
  label: string;
  chats: ChatSummary[];
}

export function getChatPreview(summary: ChatSummary): string {
  return summary.lastUserMessage?.trim()
    || summary.lastAssistantMessage?.trim()
    || 'Open conversation';
}

export function groupChatsByDate(
  summaries: ChatSummary[],
  now = new Date(),
): ChatDateGroup[] {
  const sorted = [...summaries].sort(
    (left, right) => new Date(right.updatedAt).getTime() - new Date(left.updatedAt).getTime(),
  );

  return sorted.reduce<ChatDateGroup[]>((groups, chat) => {
    const date = new Date(chat.updatedAt);
    const key = format(date, 'yyyy-MM-dd');
    const existing = groups.find((group) => group.key === key);
    if (existing !== undefined) {
      existing.chats.push(chat);
      return groups;
    }
    groups.push({
      key,
      label: isSameDay(date, now)
        ? `Today, ${format(date, 'd MMM yyyy')}`
        : format(date, 'EEE, d MMM yyyy'),
      chats: [chat],
    });
    return groups;
  }, []);
}

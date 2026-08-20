import { format, isSameDay } from 'date-fns';

import type { ChatSummary } from '../repositories/conversationRepository';

export type { ChatSummary } from '../repositories/conversationRepository';

export interface ChatDateGroup {
  key: string;
  label: string;
  chats: ChatSummary[];
}

const GENERIC_CHAT_TITLES = new Set(['voice reflection', 'untitled chat', 'untitled conversation']);

function concise(value: string, limit = 51): string {
  const normalized = value.trim().replace(/\s+/g, ' ');
  return normalized.length <= limit ? normalized : `${normalized.slice(0, limit).trimEnd()}…`;
}

export function getChatTitle(summary: ChatSummary): string {
  const title = summary.title?.trim();
  if (title && !GENERIC_CHAT_TITLES.has(title.toLowerCase())) return title;
  const topic = summary.lastUserMessage?.trim() || summary.lastAssistantMessage?.trim();
  return topic ? concise(topic) : 'Untitled conversation';
}

export function getChatPreview(summary: ChatSummary): string {
  return summary.lastMessage?.trim()
    || summary.lastUserMessage?.trim()
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

import type { ChatCardSource } from './chatCardExpansion';

export type ChatConversationRouteParam = string | string[] | undefined;

export function resolveInitialChatConversationId(
  routeConversationId: ChatConversationRouteParam,
  activeConversationId: string | null,
  forceFresh = false,
): string | null {
  if (forceFresh) return null;
  const candidate = Array.isArray(routeConversationId)
    ? routeConversationId[0]
    : routeConversationId;
  return candidate !== undefined && candidate.trim().length > 0
    ? candidate
    : activeConversationId;
}

export function chatConversationRoute(
  conversationId: string,
  source?: ChatCardSource | null,
  title?: string,
) {
  const context = title ? { conversationId, title } : { conversationId };
  return {
    pathname: '/chat' as const,
    params: source ? {
      ...context,
      cardX: String(source.frame.x),
      cardY: String(source.frame.y),
      cardWidth: String(source.frame.width),
      cardHeight: String(source.frame.height),
      listScrollY: String(source.listScrollY),
      sourceViewportWidth: String(source.viewport.width),
      sourceViewportHeight: String(source.viewport.height),
    } : context,
  };
}

export function chatThreadRoute(conversationId: string) {
  return {
    pathname: '/thread/[id]' as const,
    params: { id: conversationId },
  };
}

export type ChatPresentation = 'route' | 'overlay';

export function startFreshCapture(actions: {
  clearActiveConversation(): void;
  openCapture(): void;
}): void {
  actions.clearActiveConversation();
  actions.openCapture();
}

export function closeChatPresentation(
  presentation: ChatPresentation,
  actions: { closeRoute(): void; closeOverlay(): void },
): void {
  if (presentation === 'route') actions.closeRoute();
  else actions.closeOverlay();
}

export function isConversationCacheCurrent(
  targetConversationId: string | null,
  cachedConversationId: string | null,
): boolean {
  return targetConversationId !== null && targetConversationId === cachedConversationId;
}

const EMPTY_CONVERSATION_MESSAGES: never[] = [];

export function selectConversationMessages<T>(
  targetConversationId: string | null,
  cachedConversationId: string | null,
  cachedMessages: T[],
): T[] {
  return isConversationCacheCurrent(targetConversationId, cachedConversationId)
    ? cachedMessages
    : EMPTY_CONVERSATION_MESSAGES;
}

export function returnFromRoutedChat(actions: {
  canGoBack(): boolean;
  back(): void;
  replace(path: '/'): void;
}): void {
  if (actions.canGoBack()) actions.back();
  else actions.replace('/');
}

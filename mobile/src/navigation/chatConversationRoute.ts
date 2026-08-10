export type ChatConversationRouteParam = string | string[] | undefined;

export function resolveInitialChatConversationId(
  routeConversationId: ChatConversationRouteParam,
  activeConversationId: string | null,
): string | null {
  const candidate = Array.isArray(routeConversationId)
    ? routeConversationId[0]
    : routeConversationId;
  return candidate !== undefined && candidate.trim().length > 0
    ? candidate
    : activeConversationId;
}

export function chatConversationRoute(conversationId: string) {
  return {
    pathname: '/chat' as const,
    params: { conversationId },
  };
}

export type ChatPresentation = 'route' | 'overlay';

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

export function returnFromRoutedChat(actions: {
  canGoBack(): boolean;
  back(): void;
  replace(path: '/'): void;
}): void {
  if (actions.canGoBack()) actions.back();
  else actions.replace('/');
}

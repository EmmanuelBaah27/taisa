import React from 'react';
import { Pressable, Text } from 'react-native';
import { router } from 'expo-router';

import { ThreadResumeAction } from '../../components/ThreadResumeAction';
import {
  chatConversationRoute,
  closeChatPresentation,
  isConversationCacheCurrent,
  returnFromRoutedChat,
  resolveInitialChatConversationId,
  selectConversationMessages,
  startFreshCapture,
  voiceCancelAccessibilityLabel,
  voiceCancelDestination,
} from '../chatConversationRoute';

jest.mock('expo-router', () => ({
  router: {
    push: jest.fn(),
  },
}));

const push = router.push as jest.Mock;

function descendants(node: React.ReactNode): React.ReactElement<Record<string, any>>[] {
  if (!React.isValidElement<{ children?: React.ReactNode }>(node)) return [];
  return [
    node as React.ReactElement<Record<string, any>>,
    ...React.Children.toArray(node.props.children).flatMap(descendants),
  ];
}

function textContent(node: React.ReactNode): string {
  return React.Children.toArray(node)
    .map((child) => typeof child === 'string' || typeof child === 'number'
      ? String(child)
      : React.isValidElement<{ children?: React.ReactNode }>(child)
        ? textContent(child.props.children)
        : '')
    .join('');
}

describe('durable conversation resume navigation', () => {
  beforeEach(() => {
    push.mockClear();
  });

  test('a deep-linked conversation wins over empty or stale Zustand view state', () => {
    expect(resolveInitialChatConversationId('conversation-from-history', null))
      .toBe('conversation-from-history');
    expect(resolveInitialChatConversationId(
      ['conversation-from-history', 'ignored-duplicate'],
      'stale-view-conversation',
    )).toBe('conversation-from-history');
    expect(resolveInitialChatConversationId(undefined, 'current-view-conversation'))
      .toBe('current-view-conversation');
  });

  test('a fresh overlay never restores the previous active conversation snapshot', () => {
    expect(resolveInitialChatConversationId(undefined, 'failed-conversation', true)).toBeNull();
    expect(resolveInitialChatConversationId('history-conversation', 'failed-conversation', false))
      .toBe('history-conversation');
  });

  test('voice cancel returns an existing chat to reply and closes a fresh capture', () => {
    expect(voiceCancelDestination('conversation-from-history')).toBe('reply');
    expect(voiceCancelDestination(null)).toBe('close');
    expect(voiceCancelAccessibilityLabel('conversation-from-history'))
      .toBe('Cancel recording and return to chat');
    expect(voiceCancelAccessibilityLabel(null)).toBe('Cancel recording and close');
  });

  test('the resume route carries the durable SQLite conversation ID', () => {
    expect(chatConversationRoute('conversation/with private work'))
      .toEqual({
        pathname: '/chat',
        params: { conversationId: 'conversation/with private work' },
      });
  });

  test('the Chats list opens canonical chat with its measured source frame', () => {
    expect(chatConversationRoute('conversation/with private work', {
      frame: { x: 16, y: 140, width: 361, height: 72 },
      listScrollY: 248.5,
      viewport: { width: 393, height: 852 },
    }, 'Navigating a career change'))
      .toEqual({
        pathname: '/chat',
        params: {
          conversationId: 'conversation/with private work',
          title: 'Navigating a career change',
          cardX: '16',
          cardY: '140',
          cardWidth: '361',
          cardHeight: '72',
          listScrollY: '248.5',
          sourceViewportWidth: '393',
          sourceViewportHeight: '852',
        },
      });
  });

  test('a pending thread renders status and count and resumes that exact conversation', () => {
    const action = ThreadResumeAction({
      conversationId: 'conversation-1',
      pendingRequestStatus: 'transcript-confirmation-required',
      pendingProposalCount: 2,
    });
    const rendered = descendants(action);
    const labels = rendered
      .filter((element) => element.type === Text)
      .map((element) => textContent(element.props.children));
    const resumeButton = rendered.find((element) => element.type === Pressable);
    const stopPropagation = jest.fn();

    expect(labels).toEqual(expect.arrayContaining([
      'Transcript ready',
      '2 decisions waiting',
      'Resume',
    ]));
    expect(resumeButton).toBeDefined();

    resumeButton!.props.onPress({ stopPropagation });

    expect(stopPropagation).toHaveBeenCalledTimes(1);
    expect(push).toHaveBeenCalledWith({
      pathname: '/chat',
      params: { conversationId: 'conversation-1' },
    });
  });

  test('a completed thread without pending decisions has no resume affordance', () => {
    expect(ThreadResumeAction({
      conversationId: 'conversation-complete',
      pendingRequestStatus: 'completed',
      pendingProposalCount: 0,
    })).toBeNull();
  });

  test('the global record control starts fresh while durable failed work remains resumable from history', () => {
    const clearActiveConversation = jest.fn();
    const openCapture = jest.fn();

    startFreshCapture({ clearActiveConversation, openCapture });

    expect(clearActiveConversation).toHaveBeenCalledTimes(1);
    expect(openCapture).toHaveBeenCalledTimes(1);
    expect(clearActiveConversation.mock.invocationCallOrder[0])
      .toBeLessThan(openCapture.mock.invocationCallOrder[0]);
  });

  test('a routed Resume returns to history while the tabs overlay closes locally', () => {
    const closeRoute = jest.fn();
    const closeOverlay = jest.fn();

    closeChatPresentation('route', { closeRoute, closeOverlay });
    expect(closeRoute).toHaveBeenCalledTimes(1);
    expect(closeOverlay).not.toHaveBeenCalled();

    closeRoute.mockClear();
    closeChatPresentation('overlay', { closeRoute, closeOverlay });
    expect(closeOverlay).toHaveBeenCalledTimes(1);
    expect(closeRoute).not.toHaveBeenCalled();
  });

  test('messages from the previous thread stay hidden while a resumed thread loads', () => {
    expect(isConversationCacheCurrent('conversation-b', 'conversation-a')).toBe(false);
    expect(isConversationCacheCurrent('conversation-b', 'conversation-b')).toBe(true);
    expect(isConversationCacheCurrent('conversation-b', null)).toBe(false);
  });

  test('an unavailable conversation cache returns one stable empty list across rerenders', () => {
    const cachedMessages = [{ id: 'message-from-previous-thread' }];

    const firstRender = selectConversationMessages(
      'conversation-b',
      'conversation-a',
      cachedMessages,
    );
    const secondRender = selectConversationMessages(
      'conversation-b',
      'conversation-a',
      cachedMessages,
    );

    expect(firstRender).toEqual([]);
    expect(secondRender).toBe(firstRender);
  });

  test('a cold chat deep link returns home when there is no route history', () => {
    const back = jest.fn();
    const replace = jest.fn();

    returnFromRoutedChat({ canGoBack: () => false, back, replace });
    expect(replace).toHaveBeenCalledWith('/');
    expect(back).not.toHaveBeenCalled();

    replace.mockClear();
    returnFromRoutedChat({ canGoBack: () => true, back, replace });
    expect(back).toHaveBeenCalledTimes(1);
    expect(replace).not.toHaveBeenCalled();
  });
});

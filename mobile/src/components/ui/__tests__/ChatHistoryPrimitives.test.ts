import React from 'react';
import { Pressable, Text, View } from 'react-native';

import {
  CHAT_LIST_ROW_MOTION,
  ChatListRowSurface,
  createOpenOnce,
} from '../ChatListRow';
import { ThreadMessage } from '../ThreadMessage';

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

describe('chat history design-system primitives', () => {
  test('ChatListRow uses a short eased press without delaying navigation', () => {
    expect(CHAT_LIST_ROW_MOTION).toEqual({
      pressedScale: 0.97,
      pressDuration: 100,
      releaseDuration: 140,
    });
  });

  test('ChatListRow opens a conversation only once across rapid taps', () => {
    jest.useFakeTimers();
    const onOpen = jest.fn();
    const openOnce = createOpenOnce(onOpen);

    openOnce(null);
    openOnce({ x: 20, y: 100, width: 353, height: 72 });

    expect(onOpen).toHaveBeenCalledTimes(1);
    expect(onOpen).toHaveBeenCalledWith(null);

    jest.runAllTimers();
    openOnce({ x: 20, y: 100, width: 353, height: 72 });
    expect(onOpen).toHaveBeenCalledTimes(2);
    jest.useRealTimers();
  });

  test('ChatListRow exposes one accessible button with title, preview, and press behavior', () => {
    const onOpen = jest.fn();
    const tree = ChatListRowSurface({
      title: 'Discovering your strengths',
      preview: 'How to identify the skills that bring you energy',
      onOpen,
    });
    const nodes = descendants(tree);
    const button = nodes.find((node) => node.type === Pressable);
    const labels = nodes
      .filter((node) => node.type === Text)
      .map((node) => textContent(node.props.children));

    expect(button?.props.accessibilityRole).toBe('button');
    expect(button?.props.accessibilityLabel).toBe(
      'Discovering your strengths. How to identify the skills that bring you energy',
    );
    expect(button?.props.accessibilityHint).toBe('Opens this conversation');
    expect(labels).toEqual(expect.arrayContaining([
      'Discovering your strengths',
      'How to identify the skills that bring you energy',
    ]));

    expect(button?.props.onPressIn).toEqual(expect.any(Function));
    button?.props.onPressIn();
    button?.props.onPress();
    expect(onOpen).toHaveBeenCalledWith(null);
    expect(onOpen).toHaveBeenCalledTimes(1);
  });

  test('ChatListRow renders attention text only when explicitly requested', () => {
    const regular = descendants(ChatListRowSurface({ title: 'Regular', preview: 'Preview', onOpen: jest.fn() }));
    const flagged = descendants(ChatListRowSurface({
      title: 'Flagged',
      preview: 'Preview',
      needsAttention: true,
      onOpen: jest.fn(),
    }));

    expect(regular.filter((node) => node.type === Text).map((node) => textContent(node.props.children)))
      .not.toContain('Needs attention');
    expect(flagged.filter((node) => node.type === Text).map((node) => textContent(node.props.children)))
      .toContain('Needs attention');
  });

  test('ThreadMessage boxes user text and leaves assistant text unboxed', () => {
    const userNodes = descendants(ThreadMessage({ role: 'user', content: 'My message' }));
    const assistantNodes = descendants(ThreadMessage({ role: 'assistant', content: 'Taisa reply' }));
    const userContainer = userNodes.find((node) => node.type === View && String(node.props.className).includes('bg-muted'));
    const assistantContainer = assistantNodes.find((node) => node.type === View && String(node.props.className).includes('bg-muted'));

    expect(userContainer).toBeDefined();
    expect(assistantContainer).toBeUndefined();
    expect(assistantNodes.filter((node) => node.type === Text).map((node) => textContent(node.props.children)))
      .toEqual(['Taisa reply']);
  });
});

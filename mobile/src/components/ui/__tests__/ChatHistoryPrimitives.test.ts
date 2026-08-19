import React from 'react';
import { Pressable, Text, View } from 'react-native';

import { ChatListRow } from '../ChatListRow';
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
  test('ChatListRow exposes one accessible button with title, preview, and press behavior', () => {
    const onOpen = jest.fn();
    const tree = ChatListRow({
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

    button?.props.onPress();
    expect(onOpen).toHaveBeenCalledWith(null);
  });

  test('ChatListRow renders attention text only when explicitly requested', () => {
    const regular = descendants(ChatListRow({ title: 'Regular', preview: 'Preview', onOpen: jest.fn() }));
    const flagged = descendants(ChatListRow({
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

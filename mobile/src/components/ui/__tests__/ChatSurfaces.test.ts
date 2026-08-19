import React from 'react';
import { Text, TouchableOpacity, View } from 'react-native';

import { ChatMessageBubble, PendingProposalCard } from '../ChatSurfaces';
import { ChatNavBar } from '../ChatNavBar';
import { TaisaReplyCard } from '../TaisaReplyCard';

jest.mock('react-native-safe-area-context', () => ({
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));

function descendants(node: React.ReactNode): React.ReactElement<Record<string, any>>[] {
  if (!React.isValidElement<{ children?: React.ReactNode }>(node)) return [];
  return [
    node as React.ReactElement<Record<string, any>>,
    ...React.Children.toArray(node.props.children).flatMap(descendants),
  ];
}

function textContent(node: React.ReactNode): string {
  return React.Children.toArray(node).map((child) => (
    typeof child === 'string' || typeof child === 'number'
      ? String(child)
      : React.isValidElement<{ children?: React.ReactNode }>(child)
        ? textContent(child.props.children)
        : ''
  )).join('');
}

function findElementByLabel(
  node: React.ReactNode,
  label: string,
): React.ReactElement<{ label?: string; onPress?: () => void }> | null {
  for (const child of React.Children.toArray(node)) {
    if (!React.isValidElement<{
      label?: string;
      accessibilityLabel?: string;
      onPress?: () => void;
      children?: React.ReactNode;
    }>(child)) {
      continue;
    }
    if (child.props.label === label || child.props.accessibilityLabel === label) return child;
    const nested = findElementByLabel(child.props.children, label);
    if (nested !== null) return nested;
  }
  return null;
}

describe('chat design-system surfaces', () => {
  test('the Figma header uses a floating close control and the conversation title', () => {
    const header = ChatNavBar({
      onClose: jest.fn(),
      title: 'Navigating a career change',
      topInset: 47,
    } as never);
    const nodes = descendants(header);
    const close = nodes.find((node) => node.type === TouchableOpacity);
    const labels = nodes.filter((node) => node.type === Text)
      .map((node) => textContent(node.props.children));

    expect(String(close?.props.className)).toContain('rounded-full');
    expect(labels).toContain('Navigating a career change');
  });

  test('the user turn uses the neutral 32px Figma bubble', () => {
    const nodes = descendants(ChatMessageBubble({ content: 'My message' }));
    const bubble = nodes.find((node) => node.type === TouchableOpacity);

    expect(String(bubble?.props.className)).toContain('rounded-8');
    expect(String(bubble?.props.className)).toContain('bg-muted');
    expect(String(bubble?.props.className)).toContain('px-4 py-4');
  });

  test('the assistant reply is unboxed base body copy', () => {
    const nodes = descendants(TaisaReplyCard({ content: 'A reply', appearance: 'plain' }));
    const root = nodes.find((node) => node.type === View);
    const body = nodes.find((node) => node.type === Text && textContent(node.props.children) === 'A reply');

    expect(String(root?.props.className)).not.toMatch(/bg-card|border/);
    expect(String(body?.props.className)).toContain('text-base-regular');
  });

  test('an editable transcript bubble exposes the correction action semantically', () => {
    const onEdit = jest.fn();
    const bubble = ChatMessageBubble({
      content: 'Correct me',
      editable: true,
      showCorrectionHint: true,
      onEdit,
    }) as React.ReactElement<{ accessibilityLabel?: string; disabled?: boolean; onPress?: () => void }>;

    expect(bubble.props.accessibilityLabel).toBe('Correct voice transcript');
    expect(bubble.props.disabled).toBe(false);
    bubble.props.onPress?.();
    expect(onEdit).toHaveBeenCalledTimes(1);
  });

  test('a clarification card maps each visible choice to the typed resolution callback', () => {
    const onResolve = jest.fn();
    const card = PendingProposalCard({
      proposal: {
        id: 'clarification-1',
        kind: 'clarification',
        summary: 'Resolve direction',
        question: 'What should happen to the old direction?',
        status: 'pending',
      },
      onConfirm: jest.fn(),
      onResolve,
    }) as React.ReactElement<{ children?: React.ReactNode }>;

    findElementByLabel(card.props.children, 'Replace old direction')?.props.onPress?.();
    findElementByLabel(card.props.children, 'Pause old direction')?.props.onPress?.();
    findElementByLabel(card.props.children, 'Keep both')?.props.onPress?.();

    expect(onResolve.mock.calls).toEqual([
      ['clarification-1', 'replace'],
      ['clarification-1', 'pause'],
      ['clarification-1', 'coexist'],
    ]);
  });

  test('response reactions are local controls and sharing requires a separate review action', () => {
    const onReact = jest.fn();
    const onShareExample = jest.fn();
    const card = TaisaReplyCard({
      responseId: 'response-1',
      content: 'A reply',
      reaction: 'helpful',
      onReact,
      onShareExample,
    }) as React.ReactElement<{ children?: React.ReactNode }>;

    findElementByLabel(card.props.children, 'Mark response unhelpful')?.props.onPress?.();
    findElementByLabel(card.props.children, 'Review example before sharing')?.props.onPress?.();
    expect(onReact).toHaveBeenCalledWith('response-1', 'unhelpful');
    expect(onShareExample).toHaveBeenCalledWith('response-1');
  });
});

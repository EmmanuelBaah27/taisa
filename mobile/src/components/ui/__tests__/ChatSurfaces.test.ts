import React from 'react';

import { ChatMessageBubble, PendingProposalCard } from '../ChatSurfaces';
import { TaisaReplyCard } from '../TaisaReplyCard';

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

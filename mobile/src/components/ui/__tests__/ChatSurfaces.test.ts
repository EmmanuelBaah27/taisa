import React from 'react';
import { Text, TouchableOpacity, View } from 'react-native';
import { ScrollView } from 'react-native-gesture-handler';

import {
  ChatConversationSurface,
  ChatMessageBubble,
  ChatScreenShell,
  PendingProposalCard,
} from '../ChatSurfaces';
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
): React.ReactElement<{ label?: string; onPress?: () => void; onLongPress?: () => void }> | null {
  for (const child of React.Children.toArray(node)) {
    if (!React.isValidElement<{
      label?: string;
      accessibilityLabel?: string;
      onPress?: () => void;
      onLongPress?: () => void;
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
  test('the morphing white shell keeps conversation content on a separate animated layer', () => {
    const shellStyle = { transform: [{ scaleX: 0.5 }] };
    const contentStyle = { opacity: 0 };
    const shell = ChatScreenShell({
      topInset: 47,
      title: 'A conversation',
      animatedStyle: shellStyle,
      contentAnimatedStyle: contentStyle,
      onClose: jest.fn(),
      children: React.createElement(View, { testID: 'messages' }),
      footer: React.createElement(View, { testID: 'composer' }),
    });
    const animatedLayers = descendants(shell).filter((node) => (
      node.props.style === shellStyle || node.props.style === contentStyle
    ));

    expect(animatedLayers.map((node) => node.props.style)).toEqual([shellStyle, contentStyle]);
  });

  test('the shell owns one navigation bar and one footer slot for every supplied footer', () => {
    const footers = [
      React.createElement(View, { testID: 'composer-footer' }),
      React.createElement(View, { testID: 'recording-footer' }),
    ];

    for (const footer of footers) {
      const shell = ChatScreenShell({
        topInset: 47,
        title: 'Taisa',
        animatedStyle: {},
        contentAnimatedStyle: {},
        onClose: jest.fn(),
        children: React.createElement(View, { testID: 'chat-content' }),
        footer,
      });
      const nodes = descendants(shell);
      const page = nodes.find((node) => node.props.testID === 'chat-page');

      expect(nodes.filter((node) => node.type === ChatNavBar)).toHaveLength(1);
      expect(nodes.filter((node) => node.props.testID === footer.props.testID)).toHaveLength(1);
      expect(String(page?.props.className)).toContain('px-5');
    }
  });

  test('sections inherit horizontal alignment from the page instead of owning section margins', () => {
    const header = ChatNavBar({ title: 'Taisa', topInset: 47, onClose: jest.fn() });
    const surface = ChatConversationSurface({
      scrollRef: { current: null }, messages: [], activeMessageId: null,
      activeRequestKind: null, transcript: '', phase: 'idle', isBusy: false,
      error: null, microphoneUnavailable: false, pendingProposals: [], editingTranscript: null,
      onContentSizeChange: jest.fn(), onEditTranscript: jest.fn(), onChangeTranscript: jest.fn(),
      onSubmitTranscript: jest.fn(), onUseKeyboard: jest.fn(), onDiscardRecording: jest.fn(),
      onRetry: jest.fn(), onConfirmProposal: jest.fn(), onResolveProposal: jest.fn(),
    });
    const scrollView = descendants(surface).find((node) => node.type === ScrollView);

    expect(String(header.props.className)).not.toMatch(/px-/);
    expect(scrollView?.props.contentContainerStyle).not.toHaveProperty('paddingHorizontal');
  });

  test('conversation layout exposes a content-size callback for an immediate initial bottom position', () => {
    const onContentSizeChange = jest.fn();
    const surface = ChatConversationSurface({
      scrollRef: { current: null },
      messages: [],
      activeMessageId: null,
      activeRequestKind: null,
      transcript: '',
      phase: 'idle',
      isBusy: false,
      error: null,
      microphoneUnavailable: false,
      pendingProposals: [],
      editingTranscript: null,
      onContentSizeChange,
      onEditTranscript: jest.fn(),
      onChangeTranscript: jest.fn(),
      onSubmitTranscript: jest.fn(),
      onUseKeyboard: jest.fn(),
      onDiscardRecording: jest.fn(),
      onRetry: jest.fn(),
      onConfirmProposal: jest.fn(),
      onResolveProposal: jest.fn(),
    });
    const scrollView = descendants(surface).find((node) => node.type === ScrollView);

    scrollView?.props.onContentSizeChange?.(393, 1200);
    expect(onContentSizeChange).toHaveBeenCalledWith(393, 1200);
  });

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

  test('the page title occupies the middle column of the close-button row', () => {
    const header = ChatNavBar({ onClose: jest.fn(), title: 'Taisa', topInset: 47 });
    const titleSlot = descendants(header).find((node) => node.props.testID === 'chat-title-slot');
    const title = descendants(titleSlot).find((node) => (
      node.type === Text && textContent(node.props.children) === 'Taisa'
    ));

    expect(String(titleSlot?.props.className)).toContain('h-14');
    expect(String(titleSlot?.props.className)).toContain('flex-1');
    expect(String(titleSlot?.props.className)).toContain('items-center');
    expect(String(titleSlot?.props.className)).toContain('justify-center');
    expect(String(title?.props.className)).not.toContain('leading-[56px]');
  });

  test('the user turn uses a neutral 28px bubble', () => {
    const nodes = descendants(ChatMessageBubble({ content: 'My message' }));
    const bubble = nodes.find((node) => node.type === TouchableOpacity);

    expect(bubble?.props.style).toMatchObject({ borderRadius: 28 });
    expect(String(bubble?.props.className)).toContain('bg-muted');
    expect(String(bubble?.props.className)).toContain('px-4 py-4');
  });

  test('the conversation starts with only a small visible inset', () => {
    const surface = ChatConversationSurface({
      scrollRef: { current: null }, messages: [], activeMessageId: null,
      activeRequestKind: null, transcript: '', phase: 'idle', isBusy: false,
      error: null, microphoneUnavailable: false, pendingProposals: [], editingTranscript: null,
      onContentSizeChange: jest.fn(), onEditTranscript: jest.fn(), onChangeTranscript: jest.fn(),
      onSubmitTranscript: jest.fn(), onUseKeyboard: jest.fn(), onDiscardRecording: jest.fn(),
      onRetry: jest.fn(), onConfirmProposal: jest.fn(), onResolveProposal: jest.fn(),
    });
    const scrollView = descendants(surface).find((node) => node.type === ScrollView);

    expect(scrollView?.props.contentContainerStyle).toMatchObject({ paddingTop: 8 });
  });

  test('the title row stays in layout while a separate fade overlays the conversation', () => {
    const header = ChatNavBar({ onClose: jest.fn(), title: 'Taisa', topInset: 47 });
    const nodes = descendants(header);
    const fade = nodes.find((node) => node.props.testID === 'chat-header-fade');

    expect(header.props.style).toMatchObject({ paddingTop: 47 });
    expect(fade?.props.style).toMatchObject({ bottom: -20, height: 20 });
    expect(fade?.props.locations).toEqual([0, 1]);
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

  test('response reactions are revealed by long-pressing the response', () => {
    const onReact = jest.fn();
    const onShareExample = jest.fn();
    const onShowRatingOptions = jest.fn();
    const card = TaisaReplyCard({
      responseId: 'response-1',
      content: 'A reply',
      reaction: 'helpful',
      onReact,
      onShareExample,
      showRatingOptions: false,
      onShowRatingOptions,
    }) as React.ReactElement<{ children?: React.ReactNode }>;

    expect(findElementByLabel(card.props.children, 'Mark response unhelpful')).toBeNull();
    findElementByLabel(card, 'Show response rating options')?.props.onLongPress?.();
    expect(onShowRatingOptions).toHaveBeenCalledTimes(1);

    const revealedCard = TaisaReplyCard({
      responseId: 'response-1', content: 'A reply', reaction: 'helpful', onReact, onShareExample,
      showRatingOptions: true, onShowRatingOptions,
    }) as React.ReactElement<{ children?: React.ReactNode }>;
    findElementByLabel(revealedCard.props.children, 'Mark response unhelpful')?.props.onPress?.();
    findElementByLabel(revealedCard.props.children, 'Review example before sharing')?.props.onPress?.();
    expect(onReact).toHaveBeenCalledWith('response-1', 'unhelpful');
    expect(onShareExample).toHaveBeenCalledWith('response-1');
  });
});

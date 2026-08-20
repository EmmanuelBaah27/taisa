import React from 'react';
import type { SharedValue } from 'react-native-reanimated';

import { VoiceComposer, type VoiceComposerProps } from '../VoiceComposer';

jest.mock('react', () => {
  const react = jest.requireActual('react');
  return {
    ...react,
    useEffect: jest.fn(),
    useReducer: jest.fn(() => ['idle', jest.fn()]),
    useRef: jest.fn(() => ({ current: null })),
  };
});

jest.mock('react-native-reanimated', () => ({
  __esModule: true,
  default: { View: 'AnimatedView' },
  Easing: { out: (value: unknown) => value, cubic: 'cubic' },
  runOnJS: (callback: () => void) => callback,
  useAnimatedStyle: jest.fn(() => ({})),
  useSharedValue: jest.fn((value: number) => ({ value })),
  withTiming: jest.fn(),
}));

type AccessibleElement = React.ReactElement<{
  accessibilityLabel?: string;
  children?: React.ReactNode;
}>;

function accessibilityLabels(node: React.ReactNode): string[] {
  if (!React.isValidElement<{ children?: React.ReactNode }>(node)) return [];
  const element = node as AccessibleElement;
  return [
    ...(element.props.accessibilityLabel ? [element.props.accessibilityLabel] : []),
    ...React.Children.toArray(element.props.children).flatMap(accessibilityLabels),
  ];
}

const baseProps: VoiceComposerProps = {
  mode: 'voice',
  voiceState: 'recording',
  durationSeconds: 4,
  amplitude: { value: 0 } as SharedValue<number>,
  text: '',
  hasVoiceDraft: false,
  submissionFailed: false,
  recordingStartFailed: false,
  textFocusRequest: 0,
  cancelVoiceLabel: 'Cancel recording and return to chat',
  onChangeText: jest.fn(),
  onSwitchToText: jest.fn(),
  onSwitchToVoice: jest.fn(),
  onStartVoice: jest.fn(),
  onPause: jest.fn(),
  onResume: jest.fn(),
  onCancelVoice: jest.fn(),
  onDeleteText: jest.fn(),
  onDeleteVoice: jest.fn(),
  onSend: jest.fn(),
};

describe('VoiceComposer cancellation labels', () => {
  test('renders the contextual cancel label for recording and paused voice replies', () => {
    const label = 'Cancel recording and return to chat';

    expect(accessibilityLabels(VoiceComposer({ ...baseProps, voiceState: 'recording' })))
      .toContain(label);
    expect(accessibilityLabels(VoiceComposer({ ...baseProps, voiceState: 'paused' })))
      .toContain(label);
  });

  test('text composer swaps voice for send only when non-whitespace text exists', () => {
    expect(accessibilityLabels(VoiceComposer({ ...baseProps, mode: 'text', voiceState: 'none', text: '   ' })))
      .toContain('Start recording');
    expect(accessibilityLabels(VoiceComposer({ ...baseProps, mode: 'text', voiceState: 'none', text: 'Hello' })))
      .toContain('Send message');
  });
});

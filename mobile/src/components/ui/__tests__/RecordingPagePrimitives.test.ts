import React from 'react';
import fs from 'node:fs';
import path from 'node:path';

import { Button } from '../Button';
import {
  RECORDING_VOICE_MARK_PATHS,
} from '../RecordingVoiceMark';
import { ActiveRecordingSurface } from '../ActiveRecordingSurface';
import { SecondaryIconButton } from '../SecondaryIconButton';
import { VoiceReactiveTimestamp, VOICE_REACTIVE_TIMESTAMP } from '../VoiceReactiveTimestamp';

jest.mock('@shopify/react-native-skia', () => ({
  Canvas: 'Canvas',
  Fill: 'Fill',
  Shader: 'Shader',
  Skia: { RuntimeEffect: { Make: jest.fn(() => ({})) } },
}));

type PrimitiveElement = React.ReactElement<{
  children?: React.ReactNode;
  label?: string;
  size?: string;
}>;

function findElementsByType(node: React.ReactNode, type: unknown): PrimitiveElement[] {
  const matches: PrimitiveElement[] = [];
  for (const child of React.Children.toArray(node)) {
    if (!React.isValidElement<{ children?: React.ReactNode }>(child)) continue;
    if (child.type === type) matches.push(child as PrimitiveElement);
    matches.push(...findElementsByType(child.props.children, type));
  }
  return matches;
}

describe('recording page primitives', () => {
  test('Button exposes the Figma 56px primary icon size', () => {
    const button = Button({
      variant: 'primary',
      size: 'icon-lg',
      label: 'Send recording',
      icon: null,
    }) as React.ReactElement<{ className: string }>;

    expect(button.props.className).toContain('h-[56px]');
    expect(button.props.className).toContain('w-[56px]');
  });

  test('voice mark preserves the supplied paths without a motion contract', () => {
    expect(RECORDING_VOICE_MARK_PATHS).toEqual({
      left: 'M24.4282 26.8479C17.9055 28.4497 10.1559 16.8666 4.66667 16.8666',
      right: 'M7.13333 24.4666C15.1614 24.4666 20.3298 14.3333 28.3298 14.3333',
    });
  });

  test('active surface composes the Figma cancel bar and one primary send action', () => {
    const surface = ActiveRecordingSurface({
      topInset: 47,
      bottomInset: 34,
      title: 'New chat',
      greeting: 'How’s it going?',
      durationSeconds: 4,
      amplitudeLevel: 0.4,
      paused: false,
      onClose: jest.fn(),
      onCancel: jest.fn(),
      onKeyboard: jest.fn(),
      onPauseResume: jest.fn(),
      onSend: jest.fn(),
    }) as React.ReactElement<{ children?: React.ReactNode }>;

    const secondary = findElementsByType(surface.props.children, SecondaryIconButton);
    const primary = findElementsByType(surface.props.children, Button);
    const timestamp = findElementsByType(surface.props.children, VoiceReactiveTimestamp);

    expect(secondary.map((item) => item.props.label)).toEqual([
      'Close recording',
      'Cancel voice recording',
      'Switch to keyboard',
      'Pause recording',
    ]);
    expect(primary).toHaveLength(1);
    expect(primary[0].props).toMatchObject({ label: 'Send recording', size: 'icon-lg' });
    expect(timestamp).toHaveLength(1);
    expect(timestamp[0].props).toMatchObject({ durationSeconds: 4, amplitudeLevel: 0.4, paused: false });
  });

  test('reactive timestamp keeps its layout geometry while raw amplitude drives a wider canvas', () => {
    expect(VOICE_REACTIVE_TIMESTAMP).toEqual({
      width: 60,
      height: 56,
      canvasWidth: 120,
      canvasHeight: 80,
      rawAmplitude: true,
    });
  });

  test('reactive timestamp keeps Skia uniforms off the UI worklet runtime', () => {
    const source = fs.readFileSync(
      path.resolve(__dirname, '../VoiceReactiveTimestamp.tsx'),
      'utf8',
    );

    expect(source).not.toContain('useDerivedValue');
    expect(source).not.toContain('SharedValue');
  });

  test('reactive timestamp uses the slightly wider contained glow envelope', () => {
    const source = fs.readFileSync(
      path.resolve(__dirname, '../VoiceReactiveTimestamp.tsx'),
      'utf8',
    );

    expect(source).toContain('float spread = mix(0.020, 0.052, energy);');
  });
});

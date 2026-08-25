import React from 'react';
import fs from 'node:fs';
import path from 'node:path';

import { Button } from '../Button';
import {
  RECORDING_VOICE_MARK_PATHS,
  RecordingVoiceMark,
} from '../RecordingVoiceMark';
import { ActiveRecordingActionBar, ActiveRecordingContent } from '../ActiveRecordingSurface';
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
  disabled?: boolean;
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

function textContent(node: React.ReactNode): string {
  if (typeof node === 'string' || typeof node === 'number') return String(node);
  if (Array.isArray(node)) return node.map(textContent).join('');
  if (!React.isValidElement<{ children?: React.ReactNode }>(node)) return '';
  return textContent(node.props.children);
}

function actionByLabel(node: React.ReactNode, label: string): PrimitiveElement {
  const actions = [
    ...findElementsByType(node, SecondaryIconButton),
    ...findElementsByType(node, Button),
  ];
  const action = actions.find((item) => item.props.label === label);
  if (!action) throw new Error(`Could not find action with label: ${label}`);
  return action;
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

  test('active recording content owns the static mark and greeting without page-shell inputs', () => {
    const content = ActiveRecordingContent({
      greeting: 'How’s it going?',
    }) as React.ReactElement<{ children?: React.ReactNode }>;

    const source = fs.readFileSync(
      path.resolve(__dirname, '../ActiveRecordingSurface.tsx'),
      'utf8',
    );

    expect(findElementsByType(content.props.children, RecordingVoiceMark)).toHaveLength(1);
    expect(textContent(content)).toContain('How’s it going?');
    expect(source).not.toContain('topInset');
    expect(source).not.toContain('title');
    expect(source).not.toContain('onClose');
  });

  test('active recording action bar keeps cancellation and keyboard available while recording actions are disabled', () => {
    const bar = ActiveRecordingActionBar({
      durationSeconds: 4,
      amplitudeLevel: 0.4,
      paused: false,
      disabled: false,
      recordingActionDisabled: true,
      cancelLabel: 'Cancel recording and close',
      onCancel: jest.fn(),
      onKeyboard: jest.fn(),
      onPauseResume: jest.fn(),
      onSend: jest.fn(),
    }) as React.ReactElement<{ children?: React.ReactNode }>;

    const secondary = findElementsByType(bar.props.children, SecondaryIconButton);
    const primary = findElementsByType(bar.props.children, Button);
    const timestamp = findElementsByType(bar.props.children, VoiceReactiveTimestamp);

    expect(secondary.map((item) => item.props.label)).toEqual([
      'Cancel recording and close',
      'Switch to keyboard',
      'Pause recording',
    ]);
    expect(primary).toHaveLength(1);
    expect(primary[0].props).toMatchObject({ label: 'Send recording', size: 'icon-lg' });
    expect(timestamp).toHaveLength(1);
    expect(timestamp[0].props).toMatchObject({ durationSeconds: 4, amplitudeLevel: 0.4, paused: false });
    expect(actionByLabel(bar, 'Cancel recording and close').props.disabled).toBe(false);
    expect(actionByLabel(bar, 'Switch to keyboard').props.disabled).toBe(false);
    expect(actionByLabel(bar, 'Pause recording').props.disabled).toBe(true);
    expect(actionByLabel(bar, 'Send recording').props.disabled).toBe(true);
  });

  test('active recording action bar leaves footer geometry to the composer dock', () => {
    const recordingSurfaceSource = fs.readFileSync(
      path.resolve(__dirname, '../ActiveRecordingSurface.tsx'),
      'utf8',
    );
    const actionBarSource = recordingSurfaceSource.slice(
      recordingSurfaceSource.indexOf('export function ActiveRecordingActionBar'),
    );
    const storySource = fs.readFileSync(
      path.resolve(__dirname, '../ActiveRecordingSurface.stories.tsx'),
      'utf8',
    );

    expect(actionBarSource).not.toContain('bottomInset');
    expect(actionBarSource).not.toContain('absolute');
    expect(actionBarSource).not.toContain('left-0');
    expect(actionBarSource).not.toContain('right-0');
    expect(actionBarSource).not.toContain('px-4');
    expect(actionBarSource).not.toContain('Math.max');
    expect(storySource).toContain('ChatComposerDock');
    expect(storySource).not.toContain('px-4');
    expect(storySource).not.toContain('pb-[34px]');
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

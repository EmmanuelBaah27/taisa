import type { ReactElement } from 'react';
import { Pressable } from 'react-native';

import {
  SECONDARY_ICON_BUTTON_FIGMA,
  SECONDARY_ICON_BUTTON_MOTION,
  SecondaryIconButtonSurface,
} from '../SecondaryIconButton';
import { Icon } from '../Icon';

describe('SecondaryIconButton', () => {
  test('preserves the exact Figma surface contract', () => {
    expect(SECONDARY_ICON_BUTTON_FIGMA).toEqual({
      size: 56,
      iconSize: 24,
      padding: 16,
      borderRadius: 40,
      backgroundColor: 'rgba(255,255,255,0.18)',
      borderColor: 'rgba(23,23,23,0.06)',
      borderWidth: 1,
      shadowColor: '#000000',
      shadowOpacity: 0.04,
      shadowRadius: 6,
      elevation: 1,
    });
  });

  test('shares the bottom-navigation fluid scale timing', () => {
    expect(SECONDARY_ICON_BUTTON_MOTION).toEqual({
      pressedScale: 1.12,
      pressDuration: 70,
      holdDuration: 100,
      releaseDuration: 90,
    });
  });

  test('exposes an accessible disabled button surface', () => {
    const surface = SecondaryIconButtonSurface({
      label: 'Pause recording',
      icon: 'IconPause',
      disabled: true,
      onPress: jest.fn(),
    }) as ReactElement<{
      accessibilityLabel: string;
      accessibilityRole: string;
      accessibilityState: { disabled: boolean };
      disabled: boolean;
      children: ReactElement<{ name: string; size: number }>;
    }>;

    expect(surface.type).toBe(Pressable);
    expect(surface.props).toEqual(expect.objectContaining({
      accessibilityLabel: 'Pause recording',
      accessibilityRole: 'button',
      accessibilityState: { disabled: true },
      disabled: true,
    }));
    expect(surface.props.children.type).toBe(Icon);
    expect(surface.props.children.props).toEqual(expect.objectContaining({
      name: 'IconPause',
      size: 24,
    }));
  });
});

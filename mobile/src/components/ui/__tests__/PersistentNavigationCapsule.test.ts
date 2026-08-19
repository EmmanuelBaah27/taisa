import type { ReactElement, ReactNode } from 'react';
import { Animated } from 'react-native';

import {
  BOTTOM_NAVIGATION_ACTIVE_FILL,
  getBottomNavigationCapsuleFrame,
} from '../../../navigation/bottomNavigation';
import { PersistentNavigationCapsule } from '../PersistentNavigationCapsule';

type CapsuleLabel = ReactElement<{ className: string; style: unknown }>;
type CapsuleRow = ReactElement<{ children: [ReactNode, CapsuleLabel] }>;
type CapsuleElement = ReactElement<{ style: unknown; children: CapsuleRow }>;

describe('PersistentNavigationCapsule', () => {
  function renderCapsule(phase: 'resting' | 'travelling' | 'settling') {
    return PersistentNavigationCapsule({
      label: 'Chats',
      leadingVisual: null,
      frame: getBottomNavigationCapsuleFrame('logs'),
      phase,
    }) as CapsuleElement;
  }

  test('uses the selected fill only while resting', () => {
    const restingCapsule = renderCapsule('resting');
    const travellingCapsule = renderCapsule('travelling');
    const settlingCapsule = renderCapsule('settling');

    expect(restingCapsule.props.style).toContainEqual({
      backgroundColor: BOTTOM_NAVIGATION_ACTIVE_FILL,
    });
    expect(travellingCapsule.props.style).toContainEqual({ backgroundColor: 'transparent' });
    expect(settlingCapsule.props.style).toContainEqual({ backgroundColor: 'transparent' });
  });

  test('uses the loaded Inter Medium font token for its label', () => {
    const capsule = renderCapsule('resting');
    const contentRow = capsule.props.children;
    const label = contentRow.props.children[1];

    expect(label.props.className).toContain('font-sans-medium');
  });

  test('composes animated styles on an animated label', () => {
    const animatedLabelStyle = { opacity: 0.4, transform: [{ translateX: -6 }] };
    const capsule = PersistentNavigationCapsule({
      label: 'Chats',
      leadingVisual: null,
      frame: getBottomNavigationCapsuleFrame('logs'),
      phase: 'travelling',
      animatedLabelStyle,
    }) as CapsuleElement;
    const label = capsule.props.children.props.children[1];

    expect(label.type).toBe(Animated.Text);
    expect(label.props.style).toContainEqual(animatedLabelStyle);
  });

  test('uses the frame width and horizontal position', () => {
    const capsule = renderCapsule('resting');

    expect(capsule.props.style).toContainEqual({ left: 66, width: 108 });
  });
});

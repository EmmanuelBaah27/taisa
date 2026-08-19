import type { ReactElement, ReactNode } from 'react';
import { Animated } from 'react-native';

import {
  BOTTOM_NAVIGATION_ACTIVE_FILL,
  BOTTOM_NAVIGATION_CLEAR_GLASS_SURFACE,
  getBottomNavigationCapsuleFrame,
} from '../../../navigation/bottomNavigation';
import { PersistentNavigationCapsule } from '../PersistentNavigationCapsule';

type CapsuleLabel = ReactElement<{ className: string; style: unknown }>;
type CapsuleRow = ReactElement<{ children: ReactNode[]; style: unknown }>;
type CapsuleElement = ReactElement<{ style: unknown; children: ReactNode[] }>;

describe('PersistentNavigationCapsule', () => {
  function renderCapsule(phase: 'resting' | 'travelling' | 'settling') {
    return PersistentNavigationCapsule({
      label: 'Chats',
      leadingVisual: null,
      frame: getBottomNavigationCapsuleFrame('logs'),
      phase,
    }) as CapsuleElement;
  }

  test('uses the exact Figma clear-glass travelling surface', () => {
    const restingCapsule = renderCapsule('resting');
    const travellingCapsule = renderCapsule('travelling');
    const settlingCapsule = renderCapsule('settling');

    expect(BOTTOM_NAVIGATION_CLEAR_GLASS_SURFACE).toEqual({
      backgroundColor: 'rgba(255,255,255,0.04)',
      borderColor: 'rgba(23,23,23,0.04)',
      borderWidth: 1,
    });
    expect(restingCapsule.props.style).not.toContainEqual(BOTTOM_NAVIGATION_CLEAR_GLASS_SURFACE);
    expect(travellingCapsule.props.style).toContainEqual(BOTTOM_NAVIGATION_CLEAR_GLASS_SURFACE);
    expect(settlingCapsule.props.style).toContainEqual(BOTTOM_NAVIGATION_CLEAR_GLASS_SURFACE);

    const restingFill = restingCapsule.props.children[0] as ReactElement<{ style: unknown[] }>;
    const travellingFill = travellingCapsule.props.children[0] as ReactElement<{ style: unknown[] }>;
    expect(restingFill.props.style).toContainEqual({ opacity: 1 });
    expect(travellingFill.props.style).toContainEqual({ opacity: 0 });
  });

  test('renders grey as a separately animated clipped overlay', () => {
    const fillStyle = { opacity: 0.4 };
    const capsule = PersistentNavigationCapsule({
      label: 'Chats',
      leadingVisual: null,
      frame: getBottomNavigationCapsuleFrame('logs'),
      phase: 'travelling',
      animatedFillStyle: fillStyle,
    }) as CapsuleElement;
    const children = capsule.props.children as unknown as ReactElement[];
    const fill = children[0] as ReactElement<{ style: unknown }>;

    expect(capsule.props.style).toContainEqual(expect.objectContaining({ overflow: 'hidden' }));
    expect(fill.type).toBe(Animated.View);
    expect(fill.props.style).toContainEqual(expect.objectContaining({
      backgroundColor: BOTTOM_NAVIGATION_ACTIVE_FILL,
    }));
    expect(fill.props.style).toContainEqual(fillStyle);
  });

  test('uses the loaded Inter Medium font token for its label', () => {
    const capsule = renderCapsule('resting');
    const contentRow = capsule.props.children[1] as CapsuleRow;
    const label = contentRow.props.children.at(-1) as CapsuleLabel;

    expect(label.props.className).toContain('font-sans-medium');
  });

  test('keeps the outgoing label outside destination content opacity ownership', () => {
    const animatedContentStyle = { opacity: 0 };
    const outgoingLabelStyle = { opacity: 1 };
    const capsule = PersistentNavigationCapsule({
      label: 'Me',
      leadingVisual: null,
      frame: getBottomNavigationCapsuleFrame('you'),
      phase: 'travelling',
      outgoingLabel: 'Chats',
      animatedContentStyle,
      animatedOutgoingLabelStyle: outgoingLabelStyle,
    }) as CapsuleElement;
    const contentRow = capsule.props.children[1] as CapsuleRow;
    const outgoingLabel = capsule.props.children[2] as CapsuleLabel;

    expect(contentRow.props.style).toContainEqual(animatedContentStyle);
    expect(contentRow.props.children).not.toContain(outgoingLabel);
    expect(outgoingLabel.type).toBe(Animated.Text);
    expect(outgoingLabel.props.style).toContainEqual(outgoingLabelStyle);
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
    const contentRow = capsule.props.children[1] as CapsuleRow;
    const label = contentRow.props.children.at(-1) as CapsuleLabel;

    expect(label.type).toBe(Animated.Text);
    expect(label.props.style).toContainEqual(animatedLabelStyle);
  });

  test('crossfades content without fading the persistent glass capsule', () => {
    const animatedContentStyle = { opacity: 0.4 };
    const capsule = PersistentNavigationCapsule({
      label: 'Chats',
      leadingVisual: null,
      frame: getBottomNavigationCapsuleFrame('logs'),
      phase: 'travelling',
      animatedContentStyle,
    }) as CapsuleElement;
    const contentRow = capsule.props.children[1] as CapsuleRow;

    expect(capsule.props.style).not.toContainEqual(animatedContentStyle);
    expect(contentRow.props.style).toContainEqual(animatedContentStyle);
  });

  test('uses the frame width and horizontal position', () => {
    const capsule = renderCapsule('resting');

    expect(capsule.props.style).toContainEqual({ left: 66, width: 108 });
  });
});

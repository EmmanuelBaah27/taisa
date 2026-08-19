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
type CapsuleElement = ReactElement<{ style: unknown; children: [ReactElement, CapsuleRow] }>;

describe('PersistentNavigationCapsule', () => {
  function renderCapsule(phase: 'resting' | 'travelling' | 'settling') {
    return PersistentNavigationCapsule({
      label: 'Chats',
      leadingVisual: null,
      frame: getBottomNavigationCapsuleFrame('logs'),
      phase,
    }) as CapsuleElement;
  }

  test('uses an optically distinct neutral clear-glass base on white', () => {
    const restingCapsule = renderCapsule('resting');
    const travellingCapsule = renderCapsule('travelling');
    const settlingCapsule = renderCapsule('settling');

    expect(BOTTOM_NAVIGATION_CLEAR_GLASS_SURFACE).toEqual({
      backgroundColor: 'rgba(255,255,255,0.01)',
      borderColor: 'rgba(15,16,16,0.10)',
      borderWidth: 1,
      shadowColor: '#0F1010',
      shadowOpacity: 0.08,
      shadowRadius: 8,
      shadowOffset: { width: 0, height: 2 },
    });
    expect(restingCapsule.props.style).toContainEqual(BOTTOM_NAVIGATION_CLEAR_GLASS_SURFACE);
    expect(travellingCapsule.props.style).toContainEqual(BOTTOM_NAVIGATION_CLEAR_GLASS_SURFACE);
    expect(settlingCapsule.props.style).toContainEqual(BOTTOM_NAVIGATION_CLEAR_GLASS_SURFACE);
    expect(BOTTOM_NAVIGATION_CLEAR_GLASS_SURFACE.borderColor).not.toContain('255,255,255');
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
    const contentRow = capsule.props.children[1];
    const label = contentRow.props.children.at(-1) as CapsuleLabel;

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
    const label = capsule.props.children[1].props.children.at(-1) as CapsuleLabel;

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
    const contentRow = capsule.props.children[1];

    expect(capsule.props.style).not.toContainEqual(animatedContentStyle);
    expect(contentRow.props.style).toContainEqual(animatedContentStyle);
  });

  test('uses the frame width and horizontal position', () => {
    const capsule = renderCapsule('resting');

    expect(capsule.props.style).toContainEqual({ left: 66, width: 108 });
  });
});

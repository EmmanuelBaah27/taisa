import { getInteractionHaptic } from '../interactionHaptics';
import { playInteractionHaptic } from '../interactionHaptics';
import * as Haptics from 'expo-haptics';

describe('interaction haptics', () => {
  test.each([
    ['record-start', { kind: 'impact', style: 'medium' }],
    ['send', { kind: 'impact', style: 'medium' }],
    ['dismiss', { kind: 'impact', style: 'light' }],
    ['go-back', { kind: 'impact', style: 'light' }],
    ['selection', { kind: 'selection' }],
    ['destructive-confirm', { kind: 'notification', type: 'warning' }],
  ] as const)('maps %s to restrained tactile feedback', (role, expected) => {
    expect(getInteractionHaptic(role)).toEqual(expected);
  });

  test('never lets a synchronous native haptic failure escape into the action lifecycle', () => {
    jest.spyOn(Haptics, 'impactAsync').mockImplementationOnce(() => {
      throw new Error('native haptic unavailable');
    });

    expect(() => playInteractionHaptic('record-start')).not.toThrow();
  });
});

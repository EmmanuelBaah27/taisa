import { getInteractionHaptic } from '../interactionHaptics';

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
});

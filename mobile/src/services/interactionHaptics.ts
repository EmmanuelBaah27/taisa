import * as Haptics from 'expo-haptics';

export type InteractionHapticRole =
  | 'record-start'
  | 'send'
  | 'dismiss'
  | 'go-back'
  | 'selection'
  | 'destructive-confirm';

export type InteractionHaptic =
  | { kind: 'impact'; style: 'light' | 'medium' }
  | { kind: 'selection' }
  | { kind: 'notification'; type: 'warning' };

export function getInteractionHaptic(role: InteractionHapticRole): InteractionHaptic {
  if (role === 'selection') return { kind: 'selection' };
  if (role === 'destructive-confirm') return { kind: 'notification', type: 'warning' };
  return {
    kind: 'impact',
    style: role === 'record-start' || role === 'send' ? 'medium' : 'light',
  };
}

export function playInteractionHaptic(role: InteractionHapticRole): void {
  const feedback = getInteractionHaptic(role);
  if (feedback.kind === 'selection') {
    void Haptics.selectionAsync().catch(() => {});
    return;
  }
  if (feedback.kind === 'notification') {
    void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning).catch(() => {});
    return;
  }
  const style = feedback.style === 'medium'
    ? Haptics.ImpactFeedbackStyle.Medium
    : Haptics.ImpactFeedbackStyle.Light;
  void Haptics.impactAsync(style).catch(() => {});
}

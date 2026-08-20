import { Pressable, Text, View } from 'react-native';
import { router } from 'expo-router';

import type { CoachingRequestStatus } from '../repositories/coachingRequestRepository';
import { chatConversationRoute } from '../navigation/chatConversationRoute';

interface ThreadResumeActionProps {
  conversationId: string;
  pendingRequestStatus: CoachingRequestStatus | null;
  pendingProposalCount: number;
}

function requestStatusLabel(status: CoachingRequestStatus | null): string | null {
  switch (status) {
    case 'transcription-pending':
      return 'Transcription interrupted';
    case 'transcription-failed':
      return 'Transcription needs attention';
    case 'transcript-confirmation-required':
      return 'Transcript ready';
    case 'coaching-pending':
      return 'Coaching interrupted';
    case 'coaching-failed':
      return 'Coaching needs attention';
    default:
      return null;
  }
}

export function ThreadResumeAction({
  conversationId,
  pendingRequestStatus,
  pendingProposalCount,
}: ThreadResumeActionProps) {
  const statusLabel = requestStatusLabel(pendingRequestStatus);
  if (statusLabel === null && pendingProposalCount === 0) return null;

  return (
    <View className="flex-row items-center justify-between gap-2 mt-2 pt-2 border-t border-border">
      <View className="flex-1">
        {statusLabel !== null && (
          <Text className="text-foreground text-xs font-semibold">{statusLabel}</Text>
        )}
        {pendingProposalCount > 0 && (
          <Text className="text-text-tertiary text-xs">
            {pendingProposalCount} {pendingProposalCount === 1 ? 'decision' : 'decisions'} waiting
          </Text>
        )}
      </View>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel="Resume pending conversation"
        onPress={(event) => {
          event.stopPropagation();
          router.push(chatConversationRoute(conversationId));
        }}
        className="rounded-full border border-border px-3 py-1.5"
      >
        <Text className="text-foreground text-xs font-semibold">Resume</Text>
      </Pressable>
    </View>
  );
}

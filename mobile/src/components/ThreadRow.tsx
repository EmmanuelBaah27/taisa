import { Pressable, View } from 'react-native';
import { router } from 'expo-router';
import { formatDistanceToNow } from 'date-fns';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withTiming,
  withSpring,
} from 'react-native-reanimated';
import type { Thread } from '../stores/threadStore';
import { ThreadResumeAction } from './ThreadResumeAction';
import { Text } from './ui/Text';

interface ThreadRowProps {
  thread: Thread;
}

export function ThreadRow({ thread }: ThreadRowProps) {
  const relativeTime = formatDistanceToNow(new Date(thread.lastMessageAt), { addSuffix: false });
  const displayTime = thread.isLive ? 'Today' : relativeTime;

  const scale = useSharedValue(1);

  const animStyle = useAnimatedStyle(() => ({
    transform: [{ scale: scale.value }],
  }));

  return (
    <Animated.View style={animStyle}>
      <Pressable
        onPress={() => router.push(`/thread/${thread.id}`)}
        onPressIn={() => { scale.value = withTiming(0.97, { duration: 80 }); }}
        onPressOut={() => { scale.value = withSpring(1, { damping: 20, stiffness: 300 }); }}
        className="bg-card rounded-xl px-3 py-3 mb-2 border border-border"
      >
        {thread.isLive && (
          <View className="flex-row items-center gap-1 mb-1">
            <View className="w-1.5 h-1.5 rounded-full bg-primary" />
            <Text role="metadataStrong">Live</Text>
          </View>
        )}

        <View className="flex-row justify-between items-center mb-1">
          <View className="flex-1 mr-2"><Text role="labelStrong" numberOfLines={1}>{thread.title}</Text></View>
          <Text role="metadata" color="tertiary">{displayTime}</Text>
        </View>

        {thread.isVoice && thread.lastUserMessage == null ? (
          <Text role="metadata" color="secondary">〜〜〜  {formatDuration(thread.audioDurationSeconds ?? 0)} voice</Text>
        ) : (
          <Text role="metadata" color="secondary" numberOfLines={1}>
            {thread.lastUserMessage ?? ''}
          </Text>
        )}

        {thread.lastAssistantMessage != null && (
          <Text role="metadata" numberOfLines={2}>
            {thread.lastAssistantMessage}
          </Text>
        )}

        <ThreadResumeAction
          conversationId={thread.id}
          pendingRequestStatus={thread.pendingRequestStatus}
          pendingProposalCount={thread.pendingProposalCount}
        />
      </Pressable>
    </Animated.View>
  );
}

function formatDuration(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.round(seconds % 60).toString().padStart(2, '0');
  return `${m}:${s}`;
}

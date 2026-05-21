import { View, Text, Pressable } from 'react-native';
import { router } from 'expo-router';
import { formatDistanceToNow } from 'date-fns';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withTiming,
  withSpring,
} from 'react-native-reanimated';
import type { Thread } from '../stores/threadStore';

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
        onPressOut={() => { scale.value = withSpring(1, { damping: 12, stiffness: 280, mass: 0.6 }); }}
        className="bg-card rounded-xl px-3 py-3 mb-2 border border-border"
      >
        {thread.isLive && (
          <View className="flex-row items-center gap-1 mb-1">
            <View className="w-1.5 h-1.5 rounded-full bg-primary" />
            <Text className="text-lime-700 text-xs font-bold tracking-wider uppercase">Live</Text>
          </View>
        )}

        <View className="flex-row justify-between items-center mb-1">
          <Text className="text-foreground text-sm font-semibold flex-1 mr-2" numberOfLines={1}>
            {thread.title}
          </Text>
          <Text className="text-text-tertiary text-xs">{displayTime}</Text>
        </View>

        {thread.isVoice && thread.lastUserMessage == null ? (
          <Text className="text-muted-foreground text-xs mb-1">〜〜〜  {formatDuration(thread.audioDurationSeconds ?? 0)} voice</Text>
        ) : (
          <Text className="text-muted-foreground text-xs mb-1" numberOfLines={1}>
            {thread.lastUserMessage ?? ''}
          </Text>
        )}

        {thread.lastAssistantMessage != null && (
          <Text className="text-lime-700 text-xs" numberOfLines={2}>
            {thread.lastAssistantMessage}
          </Text>
        )}
      </Pressable>
    </Animated.View>
  );
}

function formatDuration(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.round(seconds % 60).toString().padStart(2, '0');
  return `${m}:${s}`;
}

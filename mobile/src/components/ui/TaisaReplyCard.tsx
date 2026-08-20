import { View, Text, TouchableOpacity } from 'react-native';
import { colors } from '../../constants/theme';
import type { ResponseReaction } from '../../repositories/responseFeedbackRepository';

export interface TaisaReplyCardProps {
  appearance?: 'card' | 'plain';
  responseId?: string;
  content: string;
  reaction?: ResponseReaction | null;
  onReact?: (responseId: string, reaction: ResponseReaction) => void;
  onShareExample?: (responseId: string) => void;
}

export function TaisaReplyCard({
  appearance = 'card',
  responseId,
  content,
  reaction = null,
  onReact,
  onShareExample,
}: TaisaReplyCardProps) {
  return (
    <View
      className={appearance === 'plain'
        ? 'mb-8 w-full'
        : 'my-1 rounded-3 rounded-tl-sm border border-border bg-card px-3 py-3'}
      style={appearance === 'plain' ? undefined : { borderLeftWidth: 2, borderLeftColor: colors.accent }}
    >
      {appearance === 'card' ? (
        <Text className="mb-1 text-lime-700 text-caption-semibold">Taisa</Text>
      ) : null}
      <Text className={appearance === 'plain'
        ? 'text-foreground text-base-regular'
        : 'text-muted-foreground text-small-regular'}>{content}</Text>
      {responseId && onReact ? (
        <View className="mt-3 flex-row items-center gap-2">
          <TouchableOpacity
            accessibilityLabel="Mark response helpful"
            className={reaction === 'helpful' ? 'rounded-full bg-muted px-3 py-2' : 'rounded-full px-3 py-2'}
            onPress={() => onReact(responseId, 'helpful')}
          >
            <Text className="text-text-tertiary text-caption-semibold">Helpful</Text>
          </TouchableOpacity>
          <TouchableOpacity
            accessibilityLabel="Mark response unhelpful"
            className={reaction === 'unhelpful' ? 'rounded-full bg-muted px-3 py-2' : 'rounded-full px-3 py-2'}
            onPress={() => onReact(responseId, 'unhelpful')}
          >
            <Text className="text-text-tertiary text-caption-semibold">Not helpful</Text>
          </TouchableOpacity>
          {reaction !== null && onShareExample ? (
            <TouchableOpacity
              accessibilityLabel="Review example before sharing"
              className="ml-auto rounded-full px-3 py-2"
              onPress={() => onShareExample(responseId)}
            >
              <Text className="text-text-tertiary text-caption-semibold">Share example</Text>
            </TouchableOpacity>
          ) : null}
        </View>
      ) : null}
    </View>
  );
}

import { View, Text } from 'react-native';
import { colors } from '../../constants/theme';
import type { ResponseReaction } from '../../repositories/responseFeedbackRepository';
import { LiquidGlassPressable } from './LiquidGlassPressable';

export interface TaisaReplyCardProps {
  appearance?: 'card' | 'plain';
  responseId?: string;
  content: string;
  reaction?: ResponseReaction | null;
  onReact?: (responseId: string, reaction: ResponseReaction) => void;
  onShareExample?: (responseId: string) => void;
  showRatingOptions?: boolean;
  onShowRatingOptions?: () => void;
}

export function TaisaReplyCard({
  appearance = 'card',
  responseId,
  content,
  reaction = null,
  onReact,
  onShareExample,
  showRatingOptions = false,
  onShowRatingOptions,
}: TaisaReplyCardProps) {
  return (
    <TouchableOpacity
      accessibilityLabel={responseId && onReact ? 'Show response rating options' : undefined}
      disabled={!responseId || !onReact}
      delayLongPress={350}
      activeOpacity={1}
      onLongPress={onShowRatingOptions}
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
      {responseId && onReact && showRatingOptions ? (
        <View className="mt-3 flex-row items-center gap-2">
          <LiquidGlassPressable
            accessibilityLabel="Mark response helpful"
            hierarchy={reaction === 'helpful' ? 'standard' : 'subtle'}
            className="px-3 py-2"
            onPress={() => onReact(responseId, 'helpful')}
          >
            <Text className="text-text-tertiary text-caption-semibold">Helpful</Text>
          </LiquidGlassPressable>
          <LiquidGlassPressable
            accessibilityLabel="Mark response unhelpful"
            hierarchy={reaction === 'unhelpful' ? 'standard' : 'subtle'}
            className="px-3 py-2"
            onPress={() => onReact(responseId, 'unhelpful')}
          >
            <Text className="text-text-tertiary text-caption-semibold">Not helpful</Text>
          </LiquidGlassPressable>
          {reaction !== null && onShareExample ? (
            <LiquidGlassPressable
              accessibilityLabel="Review example before sharing"
              hierarchy="subtle"
              className="ml-auto px-3 py-2"
              onPress={() => onShareExample(responseId)}
            >
              <Text className="text-text-tertiary text-caption-semibold">Share example</Text>
            </LiquidGlassPressable>
          ) : null}
        </View>
      ) : null}
    </TouchableOpacity>
  );
}

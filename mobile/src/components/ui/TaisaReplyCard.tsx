import { View, TouchableOpacity } from 'react-native';
import { colors } from '../../constants/theme';
import type { ResponseReaction } from '../../repositories/responseFeedbackRepository';
import { LiquidGlassPressable } from './LiquidGlassPressable';
import { Text } from './Text';

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
        <View className="mb-1"><Text role="metadataStrong" color="success">Taisa</Text></View>
      ) : null}
      <Text role={appearance === 'plain' ? 'body' : 'label'} color={appearance === 'plain' ? 'primary' : 'secondary'}>{content}</Text>
      {responseId && onReact && showRatingOptions ? (
        <View className="mt-3 flex-row items-center gap-2">
          <LiquidGlassPressable
            accessibilityLabel="Mark response helpful"
            hierarchy={reaction === 'helpful' ? 'standard' : 'subtle'}
            className="px-3 py-2"
            onPress={() => onReact(responseId, 'helpful')}
          >
            <Text role="metadataStrong" color="tertiary">Helpful</Text>
          </LiquidGlassPressable>
          <LiquidGlassPressable
            accessibilityLabel="Mark response unhelpful"
            hierarchy={reaction === 'unhelpful' ? 'standard' : 'subtle'}
            className="px-3 py-2"
            onPress={() => onReact(responseId, 'unhelpful')}
          >
            <Text role="metadataStrong" color="tertiary">Not helpful</Text>
          </LiquidGlassPressable>
          {reaction !== null && onShareExample ? (
            <LiquidGlassPressable
              accessibilityLabel="Review example before sharing"
              hierarchy="subtle"
              className="ml-auto px-3 py-2"
              onPress={() => onShareExample(responseId)}
            >
              <Text role="metadataStrong" color="tertiary">Share example</Text>
            </LiquidGlassPressable>
          ) : null}
        </View>
      ) : null}
    </TouchableOpacity>
  );
}

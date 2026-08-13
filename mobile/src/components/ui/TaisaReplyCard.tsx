import { View, Text } from 'react-native';
import { colors } from '../../constants/theme';

export interface TaisaReplyCardProps {
  content: string;
}

export function TaisaReplyCard({ content }: TaisaReplyCardProps) {
  return (
    <View
      className="my-1 rounded-3 rounded-tl-sm border border-border bg-card px-3 py-3"
      style={{ borderLeftWidth: 2, borderLeftColor: colors.accent }}
    >
      <Text className="mb-1 text-lime-700 text-caption-semibold">Taisa</Text>
      <Text className="text-muted-foreground text-small-regular">{content}</Text>
    </View>
  );
}

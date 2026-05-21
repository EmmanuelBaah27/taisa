import { View, Text } from 'react-native';

interface TaisaReplyCardProps {
  content: string;
}

export function TaisaReplyCard({ content }: TaisaReplyCardProps) {
  return (
    <View
      className="bg-card rounded-lg rounded-tl-sm px-3 py-3 my-1 border border-border"
      style={{ borderLeftWidth: 2, borderLeftColor: '#cdec1a' }}
    >
      <Text className="text-lime-700 text-xs font-bold mb-1">Taisa</Text>
      <Text className="text-muted-foreground text-sm leading-relaxed">{content}</Text>
    </View>
  );
}

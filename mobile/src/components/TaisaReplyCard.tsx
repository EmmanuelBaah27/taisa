import { View, Text } from 'react-native';

interface TaisaReplyCardProps {
  content: string;
}

export function TaisaReplyCard({ content }: TaisaReplyCardProps) {
  return (
    <View className="bg-surface rounded-lg rounded-tl-sm px-3 py-3 my-1"
      style={{ borderLeftWidth: 2, borderLeftColor: '#7C6FFF' }}>
      <Text className="text-accent text-xs font-bold mb-1">Taisa</Text>
      <Text className="text-text-secondary text-sm leading-relaxed">{content}</Text>
    </View>
  );
}

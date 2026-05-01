import { View, Text, TouchableOpacity } from 'react-native';
import { router } from 'expo-router';

interface DigestItem {
  type: string;
  color: string;
  text: string;
  cta: string;
}

interface DigestCardProps {
  headline: string;
  items: DigestItem[];
}

const dotColors: Record<string, string> = {
  accent: '#7C6FFF',
  positive: '#4ADE80',
  warning: '#FBBF24',
};

export function DigestCard({ headline, items }: DigestCardProps) {
  return (
    <View className="bg-surface rounded-xl px-4 py-4 mb-4">
      <Text className="text-accent text-xs font-bold uppercase tracking-wider mb-1">📋 Taisa's week in review</Text>
      <Text className="text-text-primary text-base font-bold mb-1">{headline}</Text>
      <Text className="text-text-tertiary text-xs mb-4">Tap any item to continue</Text>

      {items.map((item, i) => (
        <TouchableOpacity
          key={i}
          onPress={() => router.push('/recording')}
          className="flex-row items-start mb-3"
        >
          <View
            className="w-2 h-2 rounded-full mt-1 mr-3 flex-shrink-0"
            style={{ backgroundColor: dotColors[item.color] ?? '#7C6FFF' }}
          />
          <View className="flex-1">
            <Text className="text-text-secondary text-sm leading-relaxed">{item.text}</Text>
            <Text className="text-accent text-xs mt-0.5">{item.cta}</Text>
          </View>
        </TouchableOpacity>
      ))}
    </View>
  );
}

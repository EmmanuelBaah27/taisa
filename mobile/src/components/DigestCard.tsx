import { View, Text, TouchableOpacity } from 'react-native';
import { router } from 'expo-router';
import { LOCAL_CAPTURE_ROUTE } from '../navigation/localCaptureRoute';

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
  accent:   '#cdec1a',  // lime-500
  positive: '#04851a',  // green-500
  warning:  '#e46300',  // orange-500
};

export function DigestCard({ headline, items }: DigestCardProps) {
  return (
    <View className="bg-card rounded-xl px-4 py-4 mb-4 border border-border">
      <Text className="text-lime-700 text-xs font-bold uppercase tracking-wider mb-1">Taisa's week in review</Text>
      <Text className="text-foreground text-base font-bold mb-1">{headline}</Text>
      <Text className="text-text-tertiary text-xs mb-4">Tap any item to continue</Text>

      {items.map((item, i) => (
        <TouchableOpacity
          key={i}
          onPress={() => router.push(LOCAL_CAPTURE_ROUTE)}
          className="flex-row items-start mb-3"
        >
          <View
            className="w-2 h-2 rounded-full mt-1 mr-3 flex-shrink-0"
            style={{ backgroundColor: dotColors[item.color] ?? '#cdec1a' }}
          />
          <View className="flex-1">
            <Text className="text-muted-foreground text-sm leading-relaxed">{item.text}</Text>
            <Text className="text-lime-700 text-xs mt-0.5">{item.cta}</Text>
          </View>
        </TouchableOpacity>
      ))}
    </View>
  );
}

import { Pressable, View } from 'react-native';
import { router } from 'expo-router';
import { LOCAL_CAPTURE_ROUTE } from '../navigation/localCaptureRoute';
import { Text } from './ui/Text';

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

const dotClasses: Record<string, string> = {
  accent: 'bg-primary',
  positive: 'bg-success',
  warning: 'bg-warning',
};

export function DigestCard({ headline, items }: DigestCardProps) {
  return (
    <View className="bg-card rounded-xl px-4 py-4 mb-4 border border-border">
      <Text role="metadataStrong" color="secondary">Taisa's week in review</Text>
      <Text role="bodyStrong">{headline}</Text>
      <Text role="metadata" color="tertiary">Tap any item to continue</Text>

      {items.map((item, i) => (
        <Pressable
          key={i}
          onPress={() => router.push(LOCAL_CAPTURE_ROUTE)}
          className="flex-row items-start mb-3"
        >
          <View className={`w-2 h-2 rounded-full mt-1 mr-3 flex-shrink-0 ${dotClasses[item.color] ?? 'bg-primary'}`} />
          <View className="flex-1">
            <Text color="secondary">{item.text}</Text>
            <Text role="metadataStrong" color="primary">{item.cta}</Text>
          </View>
        </Pressable>
      ))}
    </View>
  );
}

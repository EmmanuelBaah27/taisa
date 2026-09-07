import { Pressable } from 'react-native';
import { router } from 'expo-router';
import { LOCAL_CAPTURE_ROUTE } from '../navigation/localCaptureRoute';
import { Text } from './ui/Text';

interface TaisaCardProps {
  eyebrow: string;
  body: string;
  cta: string;
  onPress?: () => void;
}

export function TaisaCard({ eyebrow, body, cta, onPress }: TaisaCardProps) {
  const handlePress = onPress ?? (() => router.push(LOCAL_CAPTURE_ROUTE));

  return (
    <Pressable
      onPress={handlePress}
      className="bg-card rounded-xl px-4 py-4 mb-4 border border-border border-l-2 border-l-primary"
    >
      <Text role="metadataStrong">{eyebrow}</Text>
      <Text>{body}</Text>
      <Text role="metadataStrong">{cta}</Text>
    </Pressable>
  );
}

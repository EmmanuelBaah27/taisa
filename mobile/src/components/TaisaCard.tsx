import { View, Text, TouchableOpacity } from 'react-native';
import { router } from 'expo-router';

interface TaisaCardProps {
  eyebrow: string;
  body: string;
  cta: string;
  onPress?: () => void;
}

export function TaisaCard({ eyebrow, body, cta, onPress }: TaisaCardProps) {
  const handlePress = onPress ?? (() => router.push('/recording'));

  return (
    <TouchableOpacity
      onPress={handlePress}
      className="bg-card rounded-xl px-4 py-4 mb-4 border border-border"
      style={{ borderLeftWidth: 2, borderLeftColor: '#cdec1a' }}
    >
      <Text className="text-lime-700 text-xs font-bold uppercase tracking-wider mb-2">{eyebrow}</Text>
      <Text className="text-foreground text-sm leading-relaxed mb-3">{body}</Text>
      <Text className="text-lime-700 text-xs font-semibold">{cta}</Text>
    </TouchableOpacity>
  );
}

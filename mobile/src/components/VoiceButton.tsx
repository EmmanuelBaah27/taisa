import { TouchableOpacity, View } from 'react-native';
import { router } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Icon } from './ui/Icon';
import { colors } from '../constants/theme';

interface VoiceButtonProps {
  onPress?: () => void;
}

export function VoiceButton({ onPress }: VoiceButtonProps) {
  const insets = useSafeAreaInsets();
  const handlePress = onPress ?? (() => router.push('/recording'));

  return (
    <View
      style={{
        position: 'absolute',
        bottom: insets.bottom + 16,
        left: 0,
        right: 0,
        alignItems: 'center',
        zIndex: 50,
      }}
    >
      <TouchableOpacity
        onPress={handlePress}
        activeOpacity={0.85}
        style={{
          backgroundColor: '#cdec1a',
          paddingVertical: 16,
          paddingHorizontal: 28,
          borderRadius: 48,
          shadowColor: colors.accent,
          shadowOffset: { width: 0, height: 0 },
          shadowOpacity: 0.6,
          shadowRadius: 24,
          elevation: 10,
        }}
      >
        <Icon name="IconMicrophone" size={24} color="#060707" />
      </TouchableOpacity>
    </View>
  );
}

import { TouchableOpacity, Text, View } from 'react-native';
import { router } from 'expo-router';

interface FABProps {
  onPress?: () => void;
}

export function FAB({ onPress }: FABProps) {
  const handlePress = onPress ?? (() => router.push('/recording'));

  return (
    <View className="absolute bottom-6 right-6" style={{ zIndex: 50 }}>
      <TouchableOpacity
        onPress={handlePress}
        className="w-14 h-14 rounded-full bg-accent items-center justify-center"
        style={{ elevation: 8, shadowColor: '#7C6FFF', shadowOffset: { width: 0, height: 4 }, shadowOpacity: 0.4, shadowRadius: 8 }}
      >
        <Text className="text-white text-2xl font-light">+</Text>
      </TouchableOpacity>
    </View>
  );
}

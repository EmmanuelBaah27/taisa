import { View, Text, TouchableOpacity } from 'react-native';
import { Icon } from './Icon';

export interface ChatNavBarProps {
  onClose: () => void;
}

export function ChatNavBar({ onClose }: ChatNavBarProps) {
  return (
    <View className="flex-row items-center px-4 pt-14 pb-3">
      <TouchableOpacity onPress={onClose} className="w-10 items-start">
        <Icon name="IconChevronDownMedium" size={20} color="#898989" />
      </TouchableOpacity>
      <Text className="flex-1 text-center text-foreground text-base-medium">
        Taisa
      </Text>
      <View className="w-10" />
    </View>
  );
}

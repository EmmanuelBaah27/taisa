import { View, Text, TouchableOpacity } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Icon } from './Icon';
import { colors } from '../../constants/theme';

export interface ChatNavBarProps {
  onClose: () => void;
}

export function ChatNavBar({ onClose }: ChatNavBarProps) {
  const insets = useSafeAreaInsets();

  return (
    <View
      className="flex-row items-center px-4 pb-3"
      style={{ paddingTop: insets.top + 8 }}
    >
      <TouchableOpacity onPress={onClose} className="w-10 items-start">
        <Icon name="IconChevronDownMedium" size={20} color={colors.textTertiary} />
      </TouchableOpacity>
      <Text className="flex-1 text-center text-foreground text-base-medium">
        Taisa
      </Text>
      <View className="w-10" />
    </View>
  );
}

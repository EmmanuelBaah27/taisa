import { View, Text, TouchableOpacity } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { Icon } from './Icon';
import { colors } from '../../constants/theme';

export interface ChatNavBarProps {
  title: string;
  topInset: number;
  onClose: () => void;
}

export function ChatNavBar({ title, topInset, onClose }: ChatNavBarProps) {
  return (
    <LinearGradient
      colors={[colors.background, colors.background, colors.backgroundTransparent]}
      locations={[0, 0.72, 1]}
      className="flex-row items-center pt-1"
      style={{ marginTop: topInset, marginBottom: -16, paddingBottom: 16 }}
    >
      <TouchableOpacity
        accessibilityRole="button"
        accessibilityLabel="Close conversation"
        onPress={onClose}
        className="h-14 w-14 items-center justify-center rounded-full border border-border-subtle bg-card shadow-xs"
      >
        <Icon name="IconChevronDownMedium" size={24} color={colors.textPrimary} />
      </TouchableOpacity>
      <Text
        testID="chat-title-slot"
        pointerEvents="none"
        className="h-14 flex-1 text-center text-foreground text-small-medium leading-[56px]"
        numberOfLines={1}
      >
        {title}
      </Text>
      <View className="h-14 w-14" />
    </LinearGradient>
  );
}

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
      colors={[colors.background, colors.backgroundTransparent]}
      className="relative flex-row items-center justify-between px-4 pb-1 pt-1"
      style={{ marginTop: topInset }}
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
        className="absolute left-20 right-20 text-center text-foreground text-small-medium"
        numberOfLines={1}
      >
        {title}
      </Text>
      <View className="h-14 w-14" />
    </LinearGradient>
  );
}

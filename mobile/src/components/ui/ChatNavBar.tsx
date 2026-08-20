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
    <View className="z-10 bg-background" style={{ paddingTop: topInset }}>
      <View className="flex-row items-center py-1">
        <TouchableOpacity
          accessibilityRole="button"
          accessibilityLabel="Close conversation"
          onPress={onClose}
          className="h-14 w-14 items-center justify-center rounded-full border border-border-subtle bg-card shadow-xs"
        >
          <Icon name="IconChevronDownMedium" size={24} color={colors.textPrimary} />
        </TouchableOpacity>
        <View
          testID="chat-title-slot"
          pointerEvents="none"
          className="h-14 flex-1 items-center justify-center"
        >
          <Text
            className="text-center text-foreground text-small-medium"
            numberOfLines={1}
          >
            {title}
          </Text>
        </View>
        <View className="h-14 w-14" />
      </View>
      <LinearGradient
        testID="chat-header-fade"
        pointerEvents="none"
        colors={[colors.background, colors.backgroundTransparent]}
        locations={[0, 1]}
        style={{ position: 'absolute', right: 0, bottom: -20, left: 0, height: 20 }}
      />
    </View>
  );
}

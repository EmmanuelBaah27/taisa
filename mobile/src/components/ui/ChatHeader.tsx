import { LinearGradient } from 'expo-linear-gradient';
import { Text, View } from 'react-native';

import { colors } from '../../constants/theme';
import { Icon } from './Icon';
import { LiquidGlassPressable } from './LiquidGlassPressable';

export interface ChatHeaderProps {
  title: string;
  topInset: number;
  onClose: () => void;
}

export function ChatHeader({ title, topInset, onClose }: ChatHeaderProps) {
  return (
    <View className="z-10 bg-background" style={{ paddingTop: topInset }}>
      <View className="flex-row items-center py-1">
        <LiquidGlassPressable
          accessibilityLabel="Close conversation"
          shape="circle"
          onPress={onClose}
          className="h-14 w-14"
        >
          <Icon name="IconChevronDownMedium" size={24} color={colors.textPrimary} />
        </LiquidGlassPressable>
        <View
          testID="chat-title-slot"
          pointerEvents="none"
          className="h-14 flex-1 items-center justify-center"
        >
          <Text className="text-center text-foreground text-small-medium" numberOfLines={1}>
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

import { createRef } from 'react';
import { Pressable, Text, View } from 'react-native';

import { colors } from '../../constants/theme';
import type { ChatCardFrame } from '../../navigation/chatCardExpansion';
import { Icon } from './Icon';

export interface ChatListRowProps {
  title: string;
  preview: string;
  needsAttention?: boolean;
  onOpen(frame: ChatCardFrame | null): void;
}

export function ChatListRow({
  title,
  preview,
  needsAttention = false,
  onOpen,
}: ChatListRowProps) {
  const rowRef = createRef<View>();

  function handlePress() {
    const row = rowRef.current;
    if (row === null || typeof row.measureInWindow !== 'function') {
      onOpen(null);
      return;
    }
    row.measureInWindow((x, y, width, height) => {
      onOpen(width > 0 && height > 0 ? { x, y, width, height } : null);
    });
  }

  return (
    <Pressable
      ref={rowRef}
      accessibilityRole="button"
      accessibilityLabel={`${title}. ${preview}`}
      accessibilityHint="Opens this conversation"
      onPress={handlePress}
      className="flex-row items-start gap-4 rounded-2 px-2 py-2 active:bg-muted"
    >
      <View className="h-6 w-6 items-center justify-center">
        <Icon name="IconChatBubbles" size={24} color={colors.textSecondary} />
      </View>
      <View className="min-w-0 flex-1 gap-1">
        <Text className="text-foreground text-base-medium" numberOfLines={1}>
          {title}
        </Text>
        <Text className="text-muted-foreground text-small-regular" numberOfLines={1}>
          {preview}
        </Text>
        {needsAttention ? (
          <View className="flex-row items-center gap-1">
            <Icon name="IconCircleInfo" size={16} color={colors.warning} />
            <Text className="text-warning-600 text-small-regular">Needs attention</Text>
          </View>
        ) : null}
      </View>
    </Pressable>
  );
}

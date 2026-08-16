import { useCallback } from 'react';
import { ActivityIndicator, Pressable, ScrollView, Text, View } from 'react-native';
import { router, useFocusEffect } from 'expo-router';

import { ChatListRow } from '../../src/components/ui';
import { colors } from '../../src/constants/theme';
import { useScrollContext } from '../../src/contexts/ScrollContext';
import { chatThreadRoute } from '../../src/navigation/chatConversationRoute';
import { useThreadStore } from '../../src/stores/threadStore';
import { getChatPreview, groupChatsByDate } from '../../src/utils/chatPresentation';

export default function LogsScreen() {
  const { threads, isLoadingThreads, error, fetchThreads } = useThreadStore();
  const { reportScroll } = useScrollContext();

  useFocusEffect(useCallback(() => {
    fetchThreads();
    return () => reportScroll(0);
  }, [fetchThreads, reportScroll]));

  const groups = groupChatsByDate(threads.map((thread) => ({
    id: thread.id,
    title: thread.title,
    updatedAt: thread.lastMessageAt,
    lastUserMessage: thread.lastUserMessage,
    lastAssistantMessage: thread.lastAssistantMessage,
  })));

  return (
    <View className="flex-1 bg-background">
      <Text className="px-4 pb-3 pt-3 text-foreground text-H1">Chats</Text>
      <ScrollView
        className="flex-1"
        contentContainerStyle={{ paddingHorizontal: 8, paddingBottom: 140 }}
        onScroll={(event) => reportScroll(event.nativeEvent.contentOffset.y)}
        scrollEventThrottle={16}
        showsVerticalScrollIndicator={false}
      >
        {isLoadingThreads && threads.length === 0 ? (
          <ActivityIndicator color={colors.accent} style={{ marginTop: 40 }} />
        ) : error && threads.length === 0 ? (
          <View className="items-center gap-3 px-4 pt-10">
            <Text className="text-center text-danger text-small-regular">Couldn’t load chats.</Text>
            <Pressable accessibilityRole="button" onPress={fetchThreads} className="rounded-full bg-muted px-6 py-3">
              <Text className="text-foreground text-small-semibold">Try again</Text>
            </Pressable>
          </View>
        ) : groups.length === 0 ? (
          <Text className="pt-10 text-center text-text-tertiary text-small-regular">
            No chats yet — tap the mic to start.
          </Text>
        ) : (
          groups.map((group) => (
            <View key={group.key} className="mb-5 gap-1">
              <Text className="px-2 text-muted-foreground text-small-regular">{group.label}</Text>
              {group.chats.map((chat) => (
                <ChatListRow
                  key={chat.id}
                  title={chat.title || 'Untitled chat'}
                  preview={getChatPreview(chat)}
                  onPress={() => router.push(chatThreadRoute(chat.id))}
                />
              ))}
            </View>
          ))
        )}
      </ScrollView>
    </View>
  );
}

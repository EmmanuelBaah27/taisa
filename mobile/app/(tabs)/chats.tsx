import { useCallback, useRef } from 'react';
import { ActivityIndicator, SectionList, useWindowDimensions, View } from 'react-native';
import { router, useFocusEffect } from 'expo-router';

import { ChatListRow } from '../../src/components/ui/ChatListRow';
import { LiquidGlassPressable } from '../../src/components/ui/LiquidGlassPressable';
import {
  getPageHeaderScrollInset,
  PageHeaderSurface,
} from '../../src/components/ui/PageHeaderSurface';
import { useScrollContext } from '../../src/contexts/ScrollContext';
import type { ChatCardFrame } from '../../src/navigation/chatCardExpansion';
import { chatConversationRoute } from '../../src/navigation/chatConversationRoute';
import { usePageHeaderPaddingTop } from '../../src/navigation/pageSafeArea';
import { useThreadStore } from '../../src/stores/threadStore';
import { useUIStore } from '../../src/stores/uiStore';
import { Text } from '../../src/components/ui/Text';
import { colorTokens } from '../../src/design-system/tokens';
import {
  getChatPreview,
  getChatTitle,
  groupChatsByDate,
  type ChatSummary,
} from '../../src/utils/chatPresentation';

interface ChatSection {
  key: string;
  label: string;
  data: ChatSummary[];
}

export default function ChatsScreen() {
  const pageHeaderPaddingTop = usePageHeaderPaddingTop();
  const { threads, isLoadingThreads, error, fetchThreads } = useThreadStore();
  const { reportScroll } = useScrollContext();
  const viewport = useWindowDimensions();
  const scrollRef = useRef<SectionList<ChatSummary, ChatSection>>(null);
  const scrollOffsetRef = useRef(0);

  useFocusEffect(useCallback(() => {
    const returnOffset = useUIStore.getState().consumeChatListReturn();
    let restoreFrame: number | undefined;
    let refreshFrame: number | undefined;
    if (returnOffset === null) {
      void fetchThreads();
    } else {
      scrollOffsetRef.current = returnOffset;
      reportScroll(returnOffset);
      scrollRef.current?.getScrollResponder()?.scrollTo({ y: returnOffset, animated: false });
      restoreFrame = requestAnimationFrame(() => {
        scrollRef.current?.getScrollResponder()?.scrollTo({ y: returnOffset, animated: false });
        refreshFrame = requestAnimationFrame(() => { void fetchThreads(); });
      });
    }
    return () => {
      if (restoreFrame !== undefined) cancelAnimationFrame(restoreFrame);
      if (refreshFrame !== undefined) cancelAnimationFrame(refreshFrame);
      reportScroll(0);
    };
  }, [fetchThreads, reportScroll]));

  const groups = groupChatsByDate(threads.map((thread) => ({
    id: thread.id,
    title: thread.title,
    updatedAt: thread.lastMessageAt,
    lastUserMessage: thread.lastUserMessage,
    lastAssistantMessage: thread.lastAssistantMessage,
    lastMessage: thread.lastMessage,
    recoveryState: thread.pendingRequestStatus === 'transcription-failed'
      ? 'transcription-failed-recording-available' as const
      : undefined,
  })));
  const sections: ChatSection[] = groups.map((group) => ({
    key: group.key,
    label: group.label,
    data: group.chats,
  }));

  function openChat(chat: ChatSummary, frame: ChatCardFrame | null) {
    const source = frame === null ? null : {
      frame,
      listScrollY: scrollOffsetRef.current,
      viewport: { width: viewport.width, height: viewport.height },
    };
    if (source !== null) {
      useUIStore.getState().captureChatListReturn(source.listScrollY);
    }
    router.push(chatConversationRoute(chat.id, source));
  }

  return (
    <View className="flex-1 bg-background">
      <PageHeaderSurface variant="title">
        <View className="-mt-px px-5 pb-3" style={{ paddingTop: pageHeaderPaddingTop }}>
          <Text role="heading">Chats</Text>
        </View>
      </PageHeaderSurface>
      <SectionList
        ref={scrollRef}
        className="flex-1"
        style={{ marginTop: getPageHeaderScrollInset(pageHeaderPaddingTop, 'title') }}
        sections={sections}
        contentContainerStyle={{
          paddingTop: 12,
          paddingHorizontal: 20,
          paddingBottom: 140,
        }}
        stickySectionHeadersEnabled
        keyExtractor={(chat) => chat.id}
        renderSectionHeader={({ section }) => (
          <View className="-mx-5 px-5 py-1">
            <View className="self-start rounded-full border border-neutral-200 bg-background px-3 py-1">
              <Text role="metadataStrong" color="secondary">{section.label}</Text>
            </View>
          </View>
        )}
        renderSectionFooter={() => <View className="h-5" />}
        renderItem={({ item: chat }) => (
          <ChatListRow
            title={getChatTitle(chat)}
            preview={getChatPreview(chat)}
            onOpen={(frame) => openChat(chat, frame)}
          />
        )}
        ListEmptyComponent={isLoadingThreads ? (
          <ActivityIndicator color={colorTokens.action.primary} style={{ marginTop: 40 }} />
        ) : error ? (
          <View className="items-center gap-3 px-4 pt-10">
            <Text role="label" color="danger">Couldn’t load chats.</Text>
            <LiquidGlassPressable accessibilityLabel="Try loading chats again" hierarchy="prominent" tone="accent" onPress={fetchThreads} className="px-6 py-3">
              <Text role="labelStrong">Try again</Text>
            </LiquidGlassPressable>
          </View>
        ) : (
          <View className="pt-10 items-center"><Text role="label" color="tertiary">No chats yet — tap the mic to start.</Text></View>
        )}
        onScroll={(event) => {
          scrollOffsetRef.current = Math.max(0, event.nativeEvent.contentOffset.y);
          reportScroll(scrollOffsetRef.current);
        }}
        scrollEventThrottle={16}
        showsVerticalScrollIndicator={false}
      />
    </View>
  );
}

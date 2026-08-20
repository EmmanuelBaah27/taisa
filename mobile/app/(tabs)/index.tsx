import { useCallback } from 'react';
import { View, Text, ScrollView } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { useThreadStore } from '../../src/stores/threadStore';
import { ThreadRow } from '../../src/components/ThreadRow';
import { WorkspaceHeader } from '../../src/components/WorkspaceHeader';
import { useScrollContext } from '../../src/contexts/ScrollContext';
import { localTodayState } from '../../src/services/todayLocalState';
import { getPageHeaderScrollInset } from '../../src/components/ui/PageHeaderSurface';
import { usePageHeaderPaddingTop } from '../../src/navigation/pageSafeArea';

export default function TodayScreen() {
  const { threads, fetchThreads } = useThreadStore();
  const { reportScroll } = useScrollContext();
  const pageHeaderPaddingTop = usePageHeaderPaddingTop();

  useFocusEffect(
    useCallback(() => {
      fetchThreads();
      return () => reportScroll(0);
    }, [])
  );

  const recentThreads = threads.slice(0, 3);
  const today = localTodayState(recentThreads);

  return (
    <View className="flex-1 bg-background">
      <WorkspaceHeader subtitle="Progress against goals and work over time" />
      <ScrollView
        className="flex-1"
        onScroll={(e) => reportScroll(e.nativeEvent.contentOffset.y)}
        scrollEventThrottle={16}
        contentContainerStyle={{
          paddingHorizontal: 20,
          paddingTop: getPageHeaderScrollInset(pageHeaderPaddingTop, 'workspace') + 8,
          paddingBottom: 120,
        }}
      >
        {today.kind === 'empty' ? (
          <View className="bg-card rounded-xl px-4 py-4 mb-4 border border-border">
            <Text className="text-foreground text-sm font-semibold">{today.title}</Text>
            <Text className="text-text-tertiary text-xs leading-relaxed mt-2">{today.body}</Text>
          </View>
        ) : null}

        {recentThreads.length > 0 && (
          <>
            <Text className="text-text-tertiary text-xs font-bold tracking-wider mb-3">
              Recent
            </Text>
            {recentThreads.map(thread => <ThreadRow key={thread.id} thread={thread} />)}
          </>
        )}
      </ScrollView>
    </View>
  );
}

import { useCallback } from 'react';
import { View, ScrollView } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { useThreadStore } from '../../src/stores/threadStore';
import { ThreadRow } from '../../src/components/ThreadRow';
import { WorkspaceHeader } from '../../src/components/WorkspaceHeader';
import { useScrollContext } from '../../src/contexts/ScrollContext';
import { localTodayState } from '../../src/services/todayLocalState';
import { getPageHeaderScrollInset } from '../../src/components/ui/PageHeaderSurface';
import { usePageHeaderPaddingTop } from '../../src/navigation/pageSafeArea';
import { Text } from '../../src/components/ui/Text';

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
        style={{ marginTop: getPageHeaderScrollInset(pageHeaderPaddingTop, 'workspace') }}
        onScroll={(e) => reportScroll(e.nativeEvent.contentOffset.y)}
        scrollEventThrottle={16}
        contentContainerStyle={{
          paddingHorizontal: 20,
          paddingTop: 8,
          paddingBottom: 120,
        }}
      >
        {today.kind === 'empty' ? (
          <View className="bg-card rounded-xl px-4 py-4 mb-4 border border-border">
            <Text role="bodyStrong">{today.title}</Text>
            <View className="mt-2">
              <Text role="metadata" color="tertiary">{today.body}</Text>
            </View>
          </View>
        ) : null}

        {recentThreads.length > 0 && (
          <>
            <View className="mb-3">
              <Text role="metadataStrong" color="tertiary">Recent</Text>
            </View>
            {recentThreads.map(thread => <ThreadRow key={thread.id} thread={thread} />)}
          </>
        )}
      </ScrollView>
    </View>
  );
}

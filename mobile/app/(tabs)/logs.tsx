import { useCallback, useState } from 'react';
import { View, Text, ScrollView, ActivityIndicator } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { useThreadStore } from '../../src/stores/threadStore';
import { ThreadRow } from '../../src/components/ThreadRow';
import { SearchBar } from '../../src/components/SearchBar';
import { WorkspaceHeader } from '../../src/components/WorkspaceHeader';
import { useScrollContext } from '../../src/contexts/ScrollContext';
import { colors } from '../../src/constants/theme';

export default function LogsScreen() {
  const { threads, isLoadingThreads, fetchThreads } = useThreadStore();
  const { reportScroll } = useScrollContext();
  const [query, setQuery] = useState('');

  useFocusEffect(
    useCallback(() => {
      fetchThreads();
      return () => reportScroll(0);
    }, [])
  );

  const filtered = query.trim()
    ? threads.filter(t =>
        t.title.toLowerCase().includes(query.toLowerCase()) ||
        (t.lastUserMessage ?? '').toLowerCase().includes(query.toLowerCase()) ||
        (t.lastAssistantMessage ?? '').toLowerCase().includes(query.toLowerCase())
      )
    : threads;

  return (
    <View className="flex-1 bg-background">
      <WorkspaceHeader subtitle="Your conversations and journal entries" />
      <ScrollView
        className="flex-1"
        onScroll={(e) => reportScroll(e.nativeEvent.contentOffset.y)}
        scrollEventThrottle={16}
        contentContainerStyle={{ paddingHorizontal: 20, paddingTop: 8, paddingBottom: 120 }}
      >
        <SearchBar value={query} onChangeText={setQuery} />

        {isLoadingThreads && threads.length === 0 ? (
          <ActivityIndicator color={colors.accent} style={{ marginTop: 40 }} />
        ) : filtered.length === 0 ? (
          <Text className="text-text-tertiary text-sm text-center mt-10">
            {query ? 'No logs match your search.' : 'No logs yet — tap the mic to start.'}
          </Text>
        ) : (
          filtered.map(thread => <ThreadRow key={thread.id} thread={thread} />)
        )}
      </ScrollView>
    </View>
  );
}

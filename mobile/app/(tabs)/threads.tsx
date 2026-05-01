import { useCallback, useState } from 'react';
import { View, Text, ScrollView, ActivityIndicator } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { useThreadStore } from '../../src/stores/threadStore';
import { ThreadRow } from '../../src/components/ThreadRow';
import { SearchBar } from '../../src/components/SearchBar';
import { FAB } from '../../src/components/FAB';
import { colors } from '../../src/constants/theme';

export default function ThreadsScreen() {
  const { threads, isLoadingThreads, fetchThreads } = useThreadStore();
  const [query, setQuery] = useState('');

  useFocusEffect(
    useCallback(() => {
      fetchThreads();
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
      <ScrollView className="flex-1" contentContainerStyle={{ paddingHorizontal: 16, paddingTop: 60, paddingBottom: 100 }}>
        <Text className="text-text-primary text-2xl font-bold mb-4">Threads</Text>

        <SearchBar value={query} onChangeText={setQuery} />

        {isLoadingThreads && threads.length === 0 ? (
          <ActivityIndicator color={colors.accent} style={{ marginTop: 40 }} />
        ) : filtered.length === 0 ? (
          <Text className="text-text-tertiary text-sm text-center mt-10">
            {query ? 'No threads match your search.' : 'No threads yet — tap + to start recording.'}
          </Text>
        ) : (
          filtered.map(thread => <ThreadRow key={thread.id} thread={thread} />)
        )}
      </ScrollView>

      <FAB />
    </View>
  );
}

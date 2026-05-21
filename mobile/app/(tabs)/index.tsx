import { useCallback, useState } from 'react';
import { View, Text, ScrollView, ActivityIndicator } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { useThreadStore } from '../../src/stores/threadStore';
import { ThreadRow } from '../../src/components/ThreadRow';
import { TaisaCard } from '../../src/components/TaisaCard';
import { DigestCard } from '../../src/components/DigestCard';
import { WorkspaceHeader } from '../../src/components/WorkspaceHeader';
import { colors } from '../../src/constants/theme';
import api from '../../src/services/api';

interface TodayCardData {
  type: string;
  eyebrow: string;
  body: string;
  cta: string;
}

interface DigestData {
  headline: string;
  items: Array<{ type: string; color: string; text: string; cta: string }>;
}

export default function TodayScreen() {
  const { threads, isLoadingThreads, fetchThreads } = useThreadStore();
  const [card, setCard] = useState<TodayCardData | null>(null);
  const [digest, setDigest] = useState<DigestData | null>(null);
  const [showDigest, setShowDigest] = useState(false);
  const [isLoadingToday, setIsLoadingToday] = useState(true);

  useFocusEffect(
    useCallback(() => {
      fetchThreads();
      loadTodayData();
    }, [])
  );

  const loadTodayData = async () => {
    setIsLoadingToday(true);
    try {
      const [cardRes, digestRes] = await Promise.all([
        api.get('/today/card'),
        api.get('/today/digest'),
      ]);
      setCard(cardRes.data.data.card);
      setShowDigest(digestRes.data.data.showDigest);
      setDigest(digestRes.data.data.digest ?? null);
    } catch (e) {
      // Silent fail
    } finally {
      setIsLoadingToday(false);
    }
  };

  const recentThreads = threads.slice(0, 3);

  return (
    <View className="flex-1 bg-background">
      <WorkspaceHeader subtitle="Progress against goals and work over time" />
      <ScrollView
        className="flex-1"
        contentContainerStyle={{ paddingHorizontal: 20, paddingTop: 8, paddingBottom: 120 }}
      >
        {isLoadingToday ? (
          <View className="bg-card rounded-xl px-4 py-4 mb-4 opacity-40 border border-border">
            <View className="h-2 bg-muted rounded mb-3 w-1/3" />
            <View className="h-3 bg-muted rounded mb-2 w-full" />
            <View className="h-3 bg-muted rounded w-3/4" />
          </View>
        ) : showDigest && digest ? (
          <DigestCard headline={digest.headline} items={digest.items} />
        ) : card ? (
          <TaisaCard eyebrow={card.eyebrow} body={card.body} cta={card.cta} />
        ) : null}

        {recentThreads.length > 0 && (
          <>
            <Text className="text-text-tertiary text-xs font-bold uppercase tracking-wider mb-3">
              {showDigest ? 'Last week' : 'Recent'}
            </Text>
            {isLoadingThreads && recentThreads.length === 0 ? (
              <ActivityIndicator color={colors.accent} />
            ) : (
              recentThreads.map(thread => <ThreadRow key={thread.id} thread={thread} />)
            )}
          </>
        )}
      </ScrollView>
    </View>
  );
}

import { useCallback } from 'react';
import { View, Text, ScrollView } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { WorkspaceHeader } from '../../src/components/WorkspaceHeader';
import { useScrollContext } from '../../src/contexts/ScrollContext';

export default function InsightsScreen() {
  const { reportScroll } = useScrollContext();

  useFocusEffect(useCallback(() => {
    return () => reportScroll(0);
  }, []));

  return (
    <View className="flex-1 bg-background">
      <WorkspaceHeader subtitle="Patterns and trends in your work" />
      <ScrollView
        className="flex-1"
        onScroll={(e) => reportScroll(e.nativeEvent.contentOffset.y)}
        scrollEventThrottle={16}
        contentContainerStyle={{ paddingHorizontal: 20, paddingTop: 8, paddingBottom: 120 }}
      >
        <Text className="text-muted-foreground text-base-regular text-center mt-20">
          Insights coming soon.
        </Text>
      </ScrollView>
    </View>
  );
}

import { useCallback } from 'react';
import { View, Text, ScrollView } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { useScrollContext } from '../../src/contexts/ScrollContext';
import { usePageHeaderPaddingTop } from '../../src/navigation/pageSafeArea';

export default function InsightsScreen() {
  const pageHeaderPaddingTop = usePageHeaderPaddingTop();
  const { reportScroll } = useScrollContext();

  useFocusEffect(useCallback(() => {
    return () => reportScroll(0);
  }, []));

  return (
    <View className="flex-1 bg-background">
      <Text className="text-foreground text-H1 px-5 pb-3" style={{ paddingTop: pageHeaderPaddingTop }}>Insights</Text>
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

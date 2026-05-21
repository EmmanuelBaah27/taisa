import { View, Text, ScrollView } from 'react-native';
import { WorkspaceHeader } from '../../src/components/WorkspaceHeader';

export default function InsightsScreen() {
  return (
    <View className="flex-1 bg-background">
      <WorkspaceHeader subtitle="Patterns and trends in your work" />
      <ScrollView
        className="flex-1"
        contentContainerStyle={{ paddingHorizontal: 20, paddingTop: 8, paddingBottom: 120 }}
      >
        <Text className="text-muted-foreground text-base-regular text-center mt-20">
          Insights coming soon.
        </Text>
      </ScrollView>
    </View>
  );
}

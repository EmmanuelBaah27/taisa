import { View, Text } from 'react-native';

interface ThemeTagProps {
  label: string;
}

export function ThemeTag({ label }: ThemeTagProps) {
  return (
    <View className="bg-lime-100 rounded-md px-2 py-0.5 mr-1 mb-1">
      <Text className="text-lime-700 text-xs font-semibold">{label}</Text>
    </View>
  );
}

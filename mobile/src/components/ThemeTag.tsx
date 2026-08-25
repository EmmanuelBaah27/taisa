import { View } from 'react-native';
import { Text } from './ui/Text';

interface ThemeTagProps {
  label: string;
}

export function ThemeTag({ label }: ThemeTagProps) {
  return (
    <View className="bg-lime-100 rounded-md px-2 py-0.5 mr-1 mb-1">
      <Text role="metadataStrong">{label}</Text>
    </View>
  );
}

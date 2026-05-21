import { View, TextInput, Text } from 'react-native';
import { colors } from '../constants/theme';

interface SearchBarProps {
  value: string;
  onChangeText: (text: string) => void;
  placeholder?: string;
}

export function SearchBar({ value, onChangeText, placeholder = 'Search conversations...' }: SearchBarProps) {
  return (
    <View className="bg-muted rounded-full px-4 py-2 mb-3 flex-row items-center border border-border">
      <Text className="text-text-tertiary text-base mr-2">⌕</Text>
      <TextInput
        value={value}
        onChangeText={onChangeText}
        placeholder={placeholder}
        placeholderTextColor={colors.textTertiary}
        className="flex-1 text-foreground text-sm"
        autoCapitalize="none"
        autoCorrect={false}
      />
    </View>
  );
}

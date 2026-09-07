import { TextInput, View } from 'react-native';
import { colorTokens } from '../design-system/tokens';
import { Text } from './ui/Text';

interface SearchBarProps {
  value: string;
  onChangeText: (text: string) => void;
  placeholder?: string;
}

export function SearchBar({ value, onChangeText, placeholder = 'Search conversations...' }: SearchBarProps) {
  return (
    <View className="bg-muted rounded-full px-4 py-2 mb-3 flex-row items-center border border-border">
      <Text role="body" color="tertiary">⌕</Text>
      <TextInput
        value={value}
        onChangeText={onChangeText}
        placeholder={placeholder}
        placeholderTextColor={colorTokens.text.tertiary}
        className="flex-1 text-foreground text-body"
        autoCapitalize="none"
        autoCorrect={false}
      />
    </View>
  );
}

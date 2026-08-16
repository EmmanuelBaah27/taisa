import { Text, View } from 'react-native';

export interface ThreadMessageProps {
  role: 'user' | 'assistant';
  content: string;
  inputType?: 'voice' | 'text' | null;
}

export function ThreadMessage({ role, content, inputType = null }: ThreadMessageProps) {
  if (role === 'assistant') {
    return (
      <View className="w-full">
        <Text className="text-foreground text-base-regular">{content}</Text>
      </View>
    );
  }

  return (
    <View className="items-end">
      <View className="max-w-[336px] rounded-8 bg-muted px-4 py-4">
        <Text className="text-foreground text-base-regular">{content}</Text>
        {inputType ? (
          <Text className="mt-1 text-text-tertiary text-caption-regular">
            {inputType === 'voice' ? 'Voice' : 'Text'}
          </Text>
        ) : null}
      </View>
    </View>
  );
}

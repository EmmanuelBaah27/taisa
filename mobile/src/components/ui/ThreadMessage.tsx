import { View } from 'react-native';
import { Text } from './Text';

export interface ThreadMessageProps {
  role: 'user' | 'assistant';
  content: string;
  inputType?: 'voice' | 'text' | null;
}

export function ThreadMessage({ role, content, inputType = null }: ThreadMessageProps) {
  if (role === 'assistant') {
    return (
      <View className="w-full">
        <Text>{content}</Text>
      </View>
    );
  }

  return (
    <View className="items-end">
      <View className="max-w-[336px] rounded-8 bg-muted px-4 py-4">
        <Text>{content}</Text>
        {inputType ? (
          <View className="mt-1"><Text role="metadata" color="tertiary">{inputType === 'voice' ? 'Voice' : 'Text'}</Text></View>
        ) : null}
      </View>
    </View>
  );
}

import { Text, View } from 'react-native';

export interface LiveTranscriptionTextProps {
  transcript: string;
}

export function LiveTranscriptionText({ transcript }: LiveTranscriptionTextProps) {
  const hasTranscript = transcript.length > 0;

  return (
    <View className="flex-1 items-center justify-center px-8">
      <Text
        className={`text-base-regular text-center ${
          hasTranscript ? 'text-lime-700' : 'text-text-tertiary'
        }`}
      >
        {hasTranscript ? transcript : "What's on your mind?"}
      </Text>
    </View>
  );
}

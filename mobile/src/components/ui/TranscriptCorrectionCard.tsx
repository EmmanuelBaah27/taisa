import { Text, TextInput, TouchableOpacity, View } from 'react-native';

export interface TranscriptCorrectionCardProps {
  value: string;
  disabled?: boolean;
  onChangeText: (value: string) => void;
  onCancel: () => void;
  onSubmit: () => void;
}

export function TranscriptCorrectionCard({
  value,
  disabled = false,
  onChangeText,
  onCancel,
  onSubmit,
}: TranscriptCorrectionCardProps) {
  return (
    <View className="mb-3 rounded-3 border border-border bg-background p-3">
      <Text className="mb-2 text-foreground text-small-semibold">Correct transcript</Text>
      <TextInput
        value={value}
        onChangeText={onChangeText}
        multiline
        autoFocus
        editable={!disabled}
        className="mb-3 max-h-40 rounded-3 bg-subtle px-3 py-2 text-foreground text-base-regular"
      />
      <View className="flex-row justify-end gap-2">
        <TouchableOpacity disabled={disabled} onPress={onCancel} className="rounded-full px-4 py-2">
          <Text className="text-foreground text-small-semibold">Cancel</Text>
        </TouchableOpacity>
        <TouchableOpacity disabled={disabled} onPress={onSubmit} className="rounded-full bg-muted px-4 py-2">
          <Text className="text-foreground text-small-semibold">Update response</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

import { Text, TextInput, View } from 'react-native';
import { LiquidGlassPressable } from './LiquidGlassPressable';

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
        <LiquidGlassPressable accessibilityLabel="Cancel transcript correction" hierarchy="subtle" disabled={disabled} onPress={onCancel} className="px-4 py-2">
          <Text className="text-foreground text-small-semibold">Cancel</Text>
        </LiquidGlassPressable>
        <LiquidGlassPressable accessibilityLabel="Update response" hierarchy="prominent" tone="accent" disabled={disabled} onPress={onSubmit} className="px-4 py-2">
          <Text className="text-foreground text-small-semibold">Update response</Text>
        </LiquidGlassPressable>
      </View>
    </View>
  );
}

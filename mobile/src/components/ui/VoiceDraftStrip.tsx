import { Text, TouchableOpacity, View } from 'react-native';

export interface VoiceDraftStripProps {
  label: string;
  preview?: string;
  onOpen: () => void;
  onDelete: () => void;
}

export function VoiceDraftStrip({ label, preview, onOpen, onDelete }: VoiceDraftStripProps) {
  return (
    <View className="mb-2 flex-row overflow-hidden rounded-3 border border-border bg-subtle">
      <TouchableOpacity className="min-w-0 flex-1 px-3 py-2" onPress={onOpen}>
        <Text className="text-foreground text-caption-semibold uppercase">{label}</Text>
        {preview ? <Text className="text-text-tertiary text-caption-regular" numberOfLines={1}>{preview}</Text> : null}
      </TouchableOpacity>
      <TouchableOpacity
        accessibilityLabel={`Delete ${label.toLowerCase()}`}
        className="w-10 items-center justify-center border-l border-border"
        onPress={onDelete}
      >
        <Text className="text-text-tertiary text-heading-4-regular">×</Text>
      </TouchableOpacity>
    </View>
  );
}

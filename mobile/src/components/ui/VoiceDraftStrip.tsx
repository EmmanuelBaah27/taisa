import { TouchableOpacity, View } from 'react-native';
import { LiquidGlassPressable } from './LiquidGlassPressable';
import { Text } from './Text';

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
        <Text role="metadataStrong">{label}</Text>
        {preview ? <Text role="metadata" color="tertiary" numberOfLines={1}>{preview}</Text> : null}
      </TouchableOpacity>
      <LiquidGlassPressable
        accessibilityLabel={`Delete ${label.toLowerCase()}`}
        hierarchy="subtle"
        shape="rounded"
        className="w-10 border-l border-border"
        onPress={onDelete}
      >
        <Text role="subheading" color="tertiary">×</Text>
      </LiquidGlassPressable>
    </View>
  );
}

import { Modal, Text, TouchableOpacity, View } from 'react-native';

export interface RecordingDiscardSheetProps {
  intent: 'cancel' | 'keyboard' | null;
  disabled?: boolean;
  onGoBack: () => void;
  onConfirm: () => void;
}

export function RecordingDiscardSheet({ intent, disabled, onGoBack, onConfirm }: RecordingDiscardSheetProps) {
  if (intent === null) return null;
  const keyboard = intent === 'keyboard';
  return (
    <Modal transparent visible animationType="fade" statusBarTranslucent onRequestClose={onGoBack}>
      <View className="flex-1 justify-end bg-overlay p-2" accessibilityViewIsModal>
        <View className="rounded-t-5 rounded-b-6 border border-border-subtle bg-background p-5" accessibilityRole="alert">
          <View className="gap-3">
            <Text className="text-xlg-medium text-foreground">{keyboard ? 'Switch to keyboard?' : 'You’ll lose your recording'}</Text>
            <Text className="text-base-regular text-foreground">{keyboard ? 'Your current recording will be discarded.' : 'You’ll lose your recording if you proceed'}</Text>
          </View>
          <View className="mt-7 flex-row justify-end gap-2">
            <TouchableOpacity className="h-14 items-center justify-center rounded-full border border-border-subtle bg-background px-4 shadow-sm" disabled={disabled} onPress={onGoBack} accessibilityLabel="Go back">
              <Text className="text-base-medium text-foreground">Go back</Text>
            </TouchableOpacity>
            <TouchableOpacity className="h-14 items-center justify-center rounded-full border border-border-subtle bg-background px-4 shadow-sm" disabled={disabled} onPress={onConfirm} accessibilityLabel={keyboard ? 'Switch' : 'Continue'}>
              <Text className="text-base-medium text-danger">{keyboard ? 'Switch' : 'Continue'}</Text>
            </TouchableOpacity>
          </View>
        </View>
      </View>
    </Modal>
  );
}

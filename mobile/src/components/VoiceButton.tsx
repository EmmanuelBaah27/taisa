import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { router } from 'expo-router';
import { VoiceEntryButton } from './ui';
import { useUIStore } from '../stores/uiStore';
import { useChatStore } from '../stores/chatStore';
import { startFreshCapture } from '../navigation/chatConversationRoute';

export interface VoiceButtonProps {
  onPress?: () => void;
}

export function VoiceButton({ onPress }: VoiceButtonProps) {
  const insets = useSafeAreaInsets();
  const { chatMorphing, openVoiceCapture } = useUIStore();
  const clearActiveSession = useChatStore((state) => state.clearActiveSession);

  const handlePress = onPress ?? (() => startFreshCapture({
    clearActiveConversation: clearActiveSession,
    openCapture: () => {
      openVoiceCapture();
      router.push('/chat');
    },
  }));

  return (
    <VoiceEntryButton
      bottomInset={insets.bottom}
      hidden={chatMorphing}
      onPress={handlePress}
    />
  );
}

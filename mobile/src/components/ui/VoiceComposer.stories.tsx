import type { Meta, StoryObj } from '@storybook/react-native';
import { View } from 'react-native';
import { useSharedValue } from 'react-native-reanimated';

import { colors } from '../../constants/theme';
import { VoiceComposer } from './VoiceComposer';

function Preview({ mode, voiceState, hasVoiceDraft, text }: {
  mode: 'voice' | 'text';
  voiceState: 'none' | 'ready' | 'recording' | 'paused';
  hasVoiceDraft: boolean;
  text: string;
}) {
  const amplitude = useSharedValue(0.55);
  return (
    <VoiceComposer
      mode={mode}
      voiceState={voiceState}
      durationSeconds={21}
      amplitude={amplitude}
      text={text}
      hasVoiceDraft={hasVoiceDraft}
      onChangeText={() => undefined}
      onSwitchToText={() => undefined}
      onSwitchToVoice={() => undefined}
      onStartVoice={() => undefined}
      onPause={() => undefined}
      onResume={() => undefined}
      onDeleteText={() => undefined}
      onDeleteVoice={() => undefined}
      onSend={() => undefined}
    />
  );
}

const meta: Meta<typeof VoiceComposer> = {
  title: 'Components/VoiceComposer',
  component: VoiceComposer,
  decorators: [(Story) => <View style={{ padding: 24, backgroundColor: colors.background }}><Story /></View>],
};

export default meta;
type Story = StoryObj<typeof meta>;

export const VoiceReady: Story = { render: () => <Preview mode="voice" voiceState="ready" hasVoiceDraft={false} text="" /> };
export const Recording: Story = { render: () => <Preview mode="voice" voiceState="recording" hasVoiceDraft text="" /> };
export const PausedWithTextDraft: Story = { render: () => <Preview mode="voice" voiceState="paused" hasVoiceDraft text="A typed clarification" /> };
export const KeyboardWithVoiceDraft: Story = { render: () => <Preview mode="text" voiceState="paused" hasVoiceDraft text="" /> };

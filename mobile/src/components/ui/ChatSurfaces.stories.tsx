import type { Meta, StoryObj } from '@storybook/react-native';
import { View } from 'react-native';
import {
  ChatErrorPanel,
  ChatMessageBubble,
  ChatProcessingBubble,
  PendingTranscriptBubble,
} from './ChatSurfaces';

const meta = { title: 'Patterns/ChatSurfaces' } satisfies Meta;
export default meta;
type Story = StoryObj<typeof meta>;

export const UserMessage: Story = {
  render: () => <ChatMessageBubble content="I made the trade-off visible." />,
};
export const PendingTranscript: Story = {
  render: () => <PendingTranscriptBubble transcript="I want to think through what happened." />,
};
export const Processing: Story = { render: () => <ChatProcessingBubble /> };
export const RecoverableError: Story = {
  render: () => (
    <View className="p-4">
      <ChatErrorPanel
        message="Taisa could not complete this action. Your content remains on this device."
        microphoneUnavailable={false}
        voiceRequest
        onUseKeyboard={() => undefined}
        onDiscardRecording={() => undefined}
        onRetry={() => undefined}
      />
    </View>
  ),
};

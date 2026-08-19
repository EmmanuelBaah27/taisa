import type { Meta, StoryObj } from '@storybook/react-native';
import { View } from 'react-native';

import { ActiveRecordingActionBar, ActiveRecordingContent } from './ActiveRecordingSurface';
import { ChatComposerDock } from './ChatSurfaces';

const meta: Meta<typeof ActiveRecordingActionBar> = {
  title: 'Patterns/ActiveRecordingSurface',
  component: ActiveRecordingActionBar,
  args: {
    durationSeconds: 0,
    amplitudeLevel: 0.35,
    paused: false,
    disabled: false,
    recordingActionDisabled: false,
    cancelLabel: 'Cancel recording and close',
    onCancel: () => undefined,
    onKeyboard: () => undefined,
    onPauseResume: () => undefined,
    onSend: () => undefined,
  },
  argTypes: {
    paused: { control: 'boolean' },
    disabled: { control: 'boolean' },
    recordingActionDisabled: { control: 'boolean' },
    durationSeconds: { control: 'number' },
    onCancel: { action: 'cancelled' },
    onKeyboard: { action: 'keyboard' },
    onPauseResume: { action: 'pause/resume' },
    onSend: { action: 'sent' },
  },
  decorators: [(Story) => (
    <View className="h-[852px] w-[393px] bg-background">
      <Story />
    </View>
  )],
  render: (args) => (
    <View className="flex-1">
      <ActiveRecordingContent greeting="How’s it going?" />
      <ChatComposerDock phase="listening" bottomInset={34}>
        <ActiveRecordingActionBar {...args} />
      </ChatComposerDock>
    </View>
  ),
};

export default meta;
type Story = StoryObj<typeof meta>;

export const Recording: Story = {};

export const Paused: Story = {
  args: { paused: true, durationSeconds: 24 },
};

export const Acquiring: Story = {
  args: { recordingActionDisabled: true },
};

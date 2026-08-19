import type { Meta, StoryObj } from '@storybook/react-native';
import { View } from 'react-native';

import { ActiveRecordingSurface } from './ActiveRecordingSurface';

const meta: Meta<typeof ActiveRecordingSurface> = {
  title: 'Patterns/ActiveRecordingSurface',
  component: ActiveRecordingSurface,
  args: {
    topInset: 47,
    bottomInset: 34,
    title: 'New chat',
    greeting: 'How’s it going?',
    durationSeconds: 0,
    paused: false,
    disabled: false,
    onClose: () => undefined,
    onCancel: () => undefined,
    onKeyboard: () => undefined,
    onPauseResume: () => undefined,
    onSend: () => undefined,
  },
  argTypes: {
    paused: { control: 'boolean' },
    disabled: { control: 'boolean' },
    durationSeconds: { control: 'number' },
    onClose: { action: 'closed' },
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
};

export default meta;
type Story = StoryObj<typeof meta>;

export const Recording: Story = {};

export const Paused: Story = {
  args: { paused: true, durationSeconds: 24 },
};

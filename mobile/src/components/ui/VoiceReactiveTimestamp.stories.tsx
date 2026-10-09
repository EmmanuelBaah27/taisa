import type { Meta, StoryObj } from '@storybook/react-native';
import { View } from 'react-native';

import { VoiceReactiveTimestamp } from './VoiceReactiveTimestamp';

const meta: Meta<typeof VoiceReactiveTimestamp> = {
  title: 'Components/VoiceReactiveTimestamp',
  component: VoiceReactiveTimestamp,
  args: {
    durationSeconds: 13,
    amplitudeLevel: 0.35,
    paused: false,
  },
  argTypes: {
    durationSeconds: { control: 'number' },
    paused: { control: 'boolean' },
  },
  decorators: [(Story) => (
    <View className="items-center bg-background p-8"><Story /></View>
  )],
};

export default meta;
type Story = StoryObj<typeof meta>;

export const VoiceDetected: Story = {};
export const Paused: Story = { args: { paused: true } };

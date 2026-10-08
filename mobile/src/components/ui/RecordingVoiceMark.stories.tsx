import type { Meta, StoryObj } from '@storybook/react-native';
import { View } from 'react-native';

import { RecordingVoiceMark } from './RecordingVoiceMark';

const meta: Meta<typeof RecordingVoiceMark> = {
  title: 'Components/RecordingVoiceMark',
  component: RecordingVoiceMark,
  decorators: [(Story) => (
    <View className="items-center bg-background p-8">
      <Story />
    </View>
  )],
};

export default meta;
type Story = StoryObj<typeof meta>;

export const Active: Story = {};

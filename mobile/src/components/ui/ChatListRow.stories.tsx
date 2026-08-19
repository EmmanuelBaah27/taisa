import type { Meta, StoryObj } from '@storybook/react-native';
import { View } from 'react-native';

import { ChatListRow } from './ChatListRow';

const meta: Meta<typeof ChatListRow> = {
  title: 'Patterns/ChatListRow',
  component: ChatListRow,
  args: {
    title: 'Discovering your strengths',
    preview: 'How to identify the skills that bring you the most energy and impact',
    needsAttention: false,
  },
  argTypes: {
    onPress: { action: 'pressed' },
  },
  decorators: [
    (Story) => (
      <View style={{ padding: 8, backgroundColor: '#FFFFFF' }}>
        <Story />
      </View>
    ),
  ],
};

export default meta;
type Story = StoryObj<typeof meta>;

export const Default: Story = {};
export const NeedsAttention: Story = { args: { needsAttention: true } };
export const LongContent: Story = {
  args: {
    title: 'Navigating a complex career change with competing priorities',
    preview: 'A step-by-step plan for transitioning into a role that aligns with your values and responsibilities',
  },
};

import type { Meta, StoryObj } from '@storybook/react-native';
import { View } from 'react-native';

import { ThreadMessage } from './ThreadMessage';

const meta: Meta<typeof ThreadMessage> = {
  title: 'Patterns/ThreadMessage',
  component: ThreadMessage,
  args: {
    role: 'assistant',
    content: 'You handled that conversation with more influence than you are giving yourself credit for.',
  },
  decorators: [
    (Story) => (
      <View style={{ padding: 16, backgroundColor: '#FFFFFF' }}>
        <Story />
      </View>
    ),
  ],
};

export default meta;
type Story = StoryObj<typeof meta>;

export const Assistant: Story = {};
export const User: Story = { args: { role: 'user', content: 'I led the roadmap conversation today.' } };
export const VoiceInput: Story = { args: { role: 'user', inputType: 'voice', content: 'I spoke up earlier than usual.' } };
export const LongReply: Story = {
  args: {
    content: 'The important pattern is not only that you spoke up. You framed the decision in a way that helped the group move forward, which is evidence of growing strategic influence.',
  },
};

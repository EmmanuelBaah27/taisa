import type { Meta, StoryObj } from '@storybook/react-native';
import { View } from 'react-native';

import { Icon } from './Icon';
import { SelectedNavigationItem } from './SelectedNavigationItem';

const meta: Meta<typeof SelectedNavigationItem> = {
  title: 'Components/SelectedNavigationItem',
  component: SelectedNavigationItem,
  args: {
    label: 'Chats',
    width: 108,
    leadingVisual: <Icon name="IconChatBubbles" size={24} color="#0F1010" />,
  },
  argTypes: {
    label: { control: 'text' },
    width: { control: 'number' },
    onPress: { action: 'pressed' },
  },
  decorators: [
    (Story) => (
      <View style={{ padding: 24, alignItems: 'flex-start', backgroundColor: '#FFFFFF' }}>
        <Story />
      </View>
    ),
  ],
};

export default meta;
type Story = StoryObj<typeof meta>;

export const ChatsSelected: Story = {};

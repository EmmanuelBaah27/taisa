import type { Meta, StoryObj } from '@storybook/react-native';
import { View } from 'react-native';

import { SecondaryIconButton } from './SecondaryIconButton';

const meta: Meta<typeof SecondaryIconButton> = {
  title: 'Components/SecondaryIconButton',
  component: SecondaryIconButton,
  args: {
    label: 'Pause recording',
    icon: 'IconPause',
    disabled: false,
    onPress: () => undefined,
  },
  argTypes: {
    icon: { control: 'text' },
    label: { control: 'text' },
    disabled: { control: 'boolean' },
    onPress: { action: 'pressed' },
  },
  decorators: [
    (Story) => (
      <View className="items-center bg-background p-8">
        <Story />
      </View>
    ),
  ],
};

export default meta;
type Story = StoryObj<typeof meta>;

export const Pause: Story = {};

export const Disabled: Story = {
  args: {
    disabled: true,
  },
};

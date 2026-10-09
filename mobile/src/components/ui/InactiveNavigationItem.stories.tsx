import type { Meta, StoryObj } from '@storybook/react-native';
import { View } from 'react-native';

import { InactiveNavigationItem } from './InactiveNavigationItem';

const meta: Meta<typeof InactiveNavigationItem> = {
  title: 'Components/InactiveNavigationItem',
  component: InactiveNavigationItem,
  args: {
    accessibilityLabel: 'Home',
    icon: 'IconHomeLine',
  },
  argTypes: {
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

export const HomeInactive: Story = {};

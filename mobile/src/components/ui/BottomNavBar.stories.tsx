import type { Meta, StoryObj } from '@storybook/react-native';
import { View } from 'react-native';
import { BottomNavBar } from './BottomNavBar';

const meta: Meta<typeof BottomNavBar> = {
  title: 'Patterns/BottomNavBar',
  component: BottomNavBar,
  decorators: [(Story) => <View className="h-80 bg-background"><Story /></View>],
};

export default meta;
type Story = StoryObj<typeof meta>;
export const Default: Story = {};

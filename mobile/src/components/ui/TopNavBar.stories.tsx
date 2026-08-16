import type { Meta, StoryObj } from '@storybook/react-native';
import { View } from 'react-native';
import { ScrollProvider } from '../../contexts/ScrollContext';
import { TopNavBar } from './TopNavBar';

const meta: Meta<typeof TopNavBar> = {
  title: 'Patterns/TopNavBar',
  component: TopNavBar,
  decorators: [(Story) => (
    <ScrollProvider>
      <View className="bg-background"><Story /></View>
    </ScrollProvider>
  )],
};

export default meta;
type Story = StoryObj<typeof meta>;
export const Default: Story = {};

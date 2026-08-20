import type { Meta, StoryObj } from '@storybook/react-native';
import { Text, View } from 'react-native';

import { LiquidGlassPressable } from './LiquidGlassPressable';

const meta: Meta<typeof LiquidGlassPressable> = {
  title: 'Components/LiquidGlassPressable',
  component: LiquidGlassPressable,
  args: {
    accessibilityLabel: 'Custom glass action',
    hierarchy: 'standard',
    tone: 'neutral',
    shape: 'capsule',
    disabled: false,
    onPress: () => undefined,
  },
  decorators: [(Story) => <View className="items-center bg-background p-8"><Story /></View>],
};

export default meta;
type Story = StoryObj<typeof meta>;

export const CustomContent: Story = {
  render: (args) => (
    <LiquidGlassPressable {...args} className="h-12 px-5" contentClassName="flex-1 flex-row items-center justify-center gap-2">
      <Text className="text-base-semibold text-foreground">Custom action</Text>
    </LiquidGlassPressable>
  ),
};

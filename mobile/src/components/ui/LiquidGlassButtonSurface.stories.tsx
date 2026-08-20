import type { Meta, StoryObj } from '@storybook/react-native';
import { Text, View } from 'react-native';

import { LiquidGlassButtonSurface } from './LiquidGlassButtonSurface';

const meta: Meta<typeof LiquidGlassButtonSurface> = {
  title: 'Components/LiquidGlassButtonSurface',
  component: LiquidGlassButtonSurface,
  args: {
    hierarchy: 'standard',
    tone: 'neutral',
    shape: 'capsule',
    disabled: false,
  },
  argTypes: {
    hierarchy: { control: 'select', options: ['prominent', 'standard', 'subtle'] },
    tone: { control: 'select', options: ['neutral', 'accent', 'destructive'] },
    shape: { control: 'select', options: ['capsule', 'circle', 'rounded'] },
    disabled: { control: 'boolean' },
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

export const Playground: Story = {
  render: (args) => (
    <LiquidGlassButtonSurface {...args} style={{ width: 148, height: 48 }}>
      <View className="flex-1 items-center justify-center">
        <Text className="text-base-semibold text-foreground">Glass action</Text>
      </View>
    </LiquidGlassButtonSurface>
  ),
};

export const SemanticTones: Story = {
  render: () => (
    <View className="gap-3">
      {(['neutral', 'accent', 'destructive'] as const).map((tone) => (
        <LiquidGlassButtonSurface
          key={tone}
          hierarchy="prominent"
          tone={tone}
          shape="capsule"
          style={{ width: 148, height: 48 }}
        >
          <View className="flex-1 items-center justify-center">
            <Text className="text-base-semibold text-foreground">{tone}</Text>
          </View>
        </LiquidGlassButtonSurface>
      ))}
    </View>
  ),
};

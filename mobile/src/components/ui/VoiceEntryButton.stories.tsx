import type { Meta, StoryObj } from '@storybook/react-native';
import { View } from 'react-native';
import { VoiceEntryButton } from './VoiceEntryButton';

const meta: Meta<typeof VoiceEntryButton> = {
  title: 'Patterns/VoiceEntryButton',
  component: VoiceEntryButton,
  args: { bottomInset: 16, hidden: false, onPress: () => undefined },
  argTypes: { onPress: { action: 'pressed' } },
  decorators: [(Story) => <View className="h-40 bg-background"><Story /></View>],
};

export default meta;
type Story = StoryObj<typeof meta>;
export const Default: Story = {};
export const Hidden: Story = { args: { hidden: true } };

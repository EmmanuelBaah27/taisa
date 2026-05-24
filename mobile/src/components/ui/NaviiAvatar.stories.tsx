import type { Meta, StoryObj } from '@storybook/react-native';
import { View } from 'react-native';
import { NaviiAvatar } from './NaviiAvatar';

const meta: Meta<typeof NaviiAvatar> = {
  title: 'Components/NaviiAvatar',
  component: NaviiAvatar,
  args: {
    seed: 'baah-device-uuid',
    size: 64,
  },
  decorators: [
    (Story) => (
      <View style={{ padding: 32, alignItems: 'center', backgroundColor: '#FFFFFF' }}>
        <Story />
      </View>
    ),
  ],
};

export default meta;
type Story = StoryObj<typeof meta>;

export const Default: Story = {};

export const TabBarSize: Story = {
  name: 'Tab bar (22px)',
  args: { size: 22 },
};

export const YouScreen: Story = {
  name: 'You screen (64px)',
  args: { size: 64 },
};

export const Hero: Story = {
  name: 'Hero (88px)',
  args: { size: 88 },
};

export const DifferentSeeds: Story = {
  name: 'Different seeds → different avatars',
  render: () => (
    <View style={{ flexDirection: 'row', gap: 16, flexWrap: 'wrap', justifyContent: 'center' }}>
      <NaviiAvatar seed="seed-alpha" size={56} />
      <NaviiAvatar seed="seed-beta" size={56} />
      <NaviiAvatar seed="seed-gamma" size={56} />
      <NaviiAvatar seed="seed-delta" size={56} />
    </View>
  ),
};

export const SameSeedIsStable: Story = {
  name: 'Same seed → same avatar (rendered twice)',
  render: () => (
    <View style={{ flexDirection: 'row', gap: 16 }}>
      <NaviiAvatar seed="stable-seed" size={64} />
      <NaviiAvatar seed="stable-seed" size={64} />
    </View>
  ),
};

import type { Meta, StoryObj } from '@storybook/react-native';
import { View, Text } from 'react-native';
import { Icon } from './Icon';
import type { IconName } from './Icon';

const meta: Meta<typeof Icon> = {
  title: 'Foundations/Icons',
  component: Icon,
  args: {
    name: 'IconSparkle',
    size: 20,
    color: '#0A0A0F',
  },
  argTypes: {
    name: { control: 'text' },
    size: {
      control: 'select',
      options: [12, 16, 20, 24, 32],
    },
    color: { control: 'color' },
  },
  decorators: [
    (Story) => (
      <View style={{ padding: 24, backgroundColor: '#FFFFFF' }}>
        <Story />
      </View>
    ),
  ],
};

export default meta;
type Story = StoryObj<typeof meta>;

export const Playground: Story = {};

export const Sizes: Story = {
  name: 'All Sizes',
  render: () => (
    <View style={{ gap: 20 }}>
      {([12, 16, 20, 24, 32] as const).map((size) => (
        <View key={size} style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
          <Icon name="IconSparkle" size={size} color="#0A0A0F" />
          <Text style={{ fontSize: 13, color: '#555' }}>{size}px</Text>
        </View>
      ))}
    </View>
  ),
};

const SAMPLE_ICONS: IconName[] = [
  'IconHome',
  'IconUser',
  'IconMicrophone',
  'IconBell',
  'IconStar',
  'IconPageSearch',
  'IconCheckmark1',
  'IconCrossSmall',
  'IconChevronRight',
  'IconChevronBottom',
  'IconArrowRight',
  'IconSparkle',
];

export const Showcase: Story = {
  render: () => (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 20 }}>
      {SAMPLE_ICONS.map((name) => (
        <View key={name} style={{ alignItems: 'center', gap: 6, width: 64 }}>
          <Icon name={name} size={24} color="#0A0A0F" />
          <Text style={{ fontSize: 10, color: '#888', textAlign: 'center' }}>{name.replace('Icon', '')}</Text>
        </View>
      ))}
    </View>
  ),
};

export const OnDark: Story = {
  name: 'On Dark Background',
  decorators: [
    (Story) => (
      <View style={{ padding: 24, backgroundColor: '#0A0A0F' }}>
        <Story />
      </View>
    ),
  ],
  render: () => (
    <View style={{ flexDirection: 'row', gap: 20 }}>
      {SAMPLE_ICONS.slice(0, 6).map((name) => (
        <Icon key={name} name={name} size={24} color="#FFFFFF" />
      ))}
    </View>
  ),
};

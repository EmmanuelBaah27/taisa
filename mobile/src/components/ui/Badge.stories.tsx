import type { Meta, StoryObj } from '@storybook/react-native';
import { View } from 'react-native';
import { Badge } from './Badge';

const meta: Meta<typeof Badge> = {
  title: 'Components/Badge',
  component: Badge,
  args: {
    color: 'neutral',
    appearance: 'subtle',
    size: 'default',
    children: 'Badge',
  },
  argTypes: {
    color: {
      control: 'select',
      options: ['neutral', 'yellow', 'orange', 'warning', 'success', 'info', 'danger', 'accent'],
    },
    appearance: {
      control: 'select',
      options: ['subtle', 'muted', 'outline'],
    },
    size: {
      control: 'select',
      options: ['default', 'sm'],
    },
    onDismiss: { action: 'dismissed' },
  },
  decorators: [
    (Story) => (
      <View style={{ padding: 24, flexDirection: 'row', flexWrap: 'wrap', gap: 8, backgroundColor: '#FFFFFF' }}>
        <Story />
      </View>
    ),
  ],
};

export default meta;
type Story = StoryObj<typeof meta>;

export const Default: Story = {
  args: { color: 'neutral', appearance: 'subtle', children: 'Neutral' },
};

export const Success: Story = {
  args: { color: 'success', children: 'Win' },
};

export const Warning: Story = {
  args: { color: 'warning', children: 'Stalling' },
};

export const Danger: Story = {
  args: { color: 'danger', children: 'Challenge' },
};

export const Info: Story = {
  args: { color: 'info', children: 'Decision' },
};

export const Accent: Story = {
  args: { color: 'accent', children: 'New' },
};

export const Dismissible: Story = {
  args: { color: 'neutral', children: 'Dismiss me', onDismiss: () => {} },
};

export const AllColors: Story = {
  name: 'All Colors — Subtle',
  render: () => (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
      <Badge color="neutral">Neutral</Badge>
      <Badge color="yellow">Yellow</Badge>
      <Badge color="orange">Orange</Badge>
      <Badge color="warning">Warning</Badge>
      <Badge color="success">Success</Badge>
      <Badge color="info">Info</Badge>
      <Badge color="danger">Danger</Badge>
      <Badge color="accent">Accent</Badge>
    </View>
  ),
};

export const AllAppearances: Story = {
  name: 'All Appearances — Success',
  render: () => (
    <View style={{ flexDirection: 'row', gap: 8 }}>
      <Badge color="success" appearance="subtle">Subtle</Badge>
      <Badge color="success" appearance="muted">Muted</Badge>
      <Badge color="success" appearance="outline">Outline</Badge>
    </View>
  ),
};

export const Taisa: Story = {
  name: 'Taisa — Journal Labels',
  render: () => (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
      <Badge color="success">Win</Badge>
      <Badge color="danger">Challenge</Badge>
      <Badge color="info">Decision</Badge>
      <Badge color="warning">Action Item</Badge>
      <Badge color="accent" size="sm">New insight</Badge>
    </View>
  ),
};

import type { Meta, StoryObj } from '@storybook/react-native';
import { View } from 'react-native';
import { Button } from './Button';

const meta: Meta<typeof Button> = {
  title: 'Components/Button',
  component: Button,
  args: {
    label: 'Button',
    variant: 'primary',
    size: 'default',
    loading: false,
    disabled: false,
  },
  argTypes: {
    variant: {
      control: 'select',
      options: ['primary', 'secondary', 'tertiary', 'destructive', 'secondary-destructive', 'tertiary-destructive'],
    },
    size: {
      control: 'select',
      options: ['default', 'sm', 'icon'],
    },
    loading: { control: 'boolean' },
    disabled: { control: 'boolean' },
    label: { control: 'text' },
    onPress: { action: 'pressed' },
  },
  decorators: [
    (Story) => (
      <View style={{ padding: 24, alignItems: 'flex-start', gap: 12, backgroundColor: '#FFFFFF' }}>
        <Story />
      </View>
    ),
  ],
};

export default meta;
type Story = StoryObj<typeof meta>;

export const Primary: Story = {
  args: { variant: 'primary', label: 'Log today' },
};

export const Secondary: Story = {
  args: { variant: 'secondary', label: 'Cancel' },
};

export const Tertiary: Story = {
  args: { variant: 'tertiary', label: 'Learn more' },
};

export const Destructive: Story = {
  args: { variant: 'destructive', label: 'Delete entry' },
};

export const SecondaryDestructive: Story = {
  name: 'Secondary Destructive',
  args: { variant: 'secondary-destructive', label: 'Remove' },
};

export const TertiaryDestructive: Story = {
  name: 'Tertiary Destructive',
  args: { variant: 'tertiary-destructive', label: 'Undo' },
};

export const Small: Story = {
  args: { variant: 'primary', size: 'sm', label: 'Add goal' },
};

export const Loading: Story = {
  args: { variant: 'primary', label: 'Saving…', loading: true },
};

export const Disabled: Story = {
  args: { variant: 'primary', label: 'Continue', disabled: true },
};

export const AllVariants: Story = {
  name: 'All Variants',
  render: () => (
    <View style={{ gap: 12, alignItems: 'flex-start' }}>
      <Button variant="primary" label="Primary" />
      <Button variant="secondary" label="Secondary" />
      <Button variant="tertiary" label="Tertiary" />
      <Button variant="destructive" label="Destructive" />
      <Button variant="secondary-destructive" label="Secondary Destructive" />
      <Button variant="tertiary-destructive" label="Tertiary Destructive" />
    </View>
  ),
};

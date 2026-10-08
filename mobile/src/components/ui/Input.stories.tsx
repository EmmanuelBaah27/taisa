import type { Meta, StoryObj } from '@storybook/react-native';
import { View, Text } from 'react-native';
import { Input } from './Input';

const meta: Meta<typeof Input> = {
  title: 'Components/Input',
  component: Input,
  args: {
    placeholder: 'What did you work on today?',
    size: 'default',
    error: false,
    editable: true,
  },
  argTypes: {
    size: {
      control: 'select',
      options: ['default', 'lg'],
    },
    error: { control: 'boolean' },
    editable: { control: 'boolean' },
    placeholder: { control: 'text' },
  },
  decorators: [
    (Story) => (
      <View style={{ padding: 24, gap: 8, backgroundColor: '#FFFFFF' }}>
        <Story />
      </View>
    ),
  ],
};

export default meta;
type Story = StoryObj<typeof meta>;

export const Default: Story = {
  args: { placeholder: 'What did you work on today?' },
};

export const Large: Story = {
  args: { size: 'lg', placeholder: 'Describe your session…' },
};

export const WithValue: Story = {
  name: 'With Value',
  args: { value: 'Finished the pitch deck and landed stakeholder sign-off' },
};

export const Error: Story = {
  args: { error: true, placeholder: 'This field is required' },
};

export const Disabled: Story = {
  args: { editable: false, value: 'Read only content' },
};

export const FormExample: Story = {
  name: 'Form Example',
  render: () => (
    <View style={{ gap: 16 }}>
      <View style={{ gap: 4 }}>
        <Text style={{ fontSize: 14, fontWeight: '500', color: '#0F0F0F' }}>Goal</Text>
        <Input placeholder="e.g. Land a senior design role" />
      </View>
      <View style={{ gap: 4 }}>
        <Text style={{ fontSize: 14, fontWeight: '500', color: '#0F0F0F' }}>Today's focus</Text>
        <Input size="lg" placeholder="What are you working toward this week?" />
      </View>
      <View style={{ gap: 4 }}>
        <Text style={{ fontSize: 14, fontWeight: '500', color: '#EF4444' }}>Email (required)</Text>
        <Input error placeholder="you@example.com" />
      </View>
    </View>
  ),
};

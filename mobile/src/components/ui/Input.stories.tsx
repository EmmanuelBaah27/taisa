import type { Meta, StoryObj } from '@storybook/react-native';
import { View } from 'react-native';
import { Input } from './Input';
import { colorTokens } from '../../design-system/tokens';

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
      <View style={{ padding: 24, gap: 8, backgroundColor: colorTokens.surface.app }}>
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
  args: { label: 'Email', errorMessage: 'This field is required', placeholder: 'you@example.com' },
};

export const WithHelperText: Story = {
  args: { label: 'Goal', helperText: 'Describe the outcome you want to reach.' },
};

export const Disabled: Story = {
  args: { editable: false, value: 'Read only content' },
};

export const FormExample: Story = {
  name: 'Form Example',
  render: () => (
    <View style={{ gap: 16 }}>
      <Input label="Goal" helperText="Use a concrete outcome." placeholder="e.g. Land a senior design role" />
      <Input label="Today's focus" size="lg" placeholder="What are you working toward this week?" />
      <Input label="Email (required)" errorMessage="Enter a valid email address." placeholder="you@example.com" />
    </View>
  ),
};

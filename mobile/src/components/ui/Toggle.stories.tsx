import type { Meta, StoryObj } from '@storybook/react-native';

import { Toggle } from './Toggle';

const meta: Meta<typeof Toggle> = {
  title: 'Components/Toggle',
  component: Toggle,
  args: { label: 'Require device unlock', value: false, onValueChange: () => undefined },
};

export default meta;
type Story = StoryObj<typeof meta>;
export const Default: Story = {};
export const Enabled: Story = { args: { value: true } };
export const Disabled: Story = { args: { disabled: true } };

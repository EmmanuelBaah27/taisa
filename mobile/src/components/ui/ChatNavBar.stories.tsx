import type { Meta, StoryObj } from '@storybook/react-native';
import { ChatNavBar } from './ChatNavBar';

const meta: Meta<typeof ChatNavBar> = {
  title: 'Patterns/ChatNavBar',
  component: ChatNavBar,
  args: { onClose: () => undefined },
  argTypes: { onClose: { action: 'closed' } },
};

export default meta;
type Story = StoryObj<typeof meta>;
export const Default: Story = {};
export const AccessibilityTextScaling: Story = {
  parameters: { notes: 'Verify the title and close control at the largest device text setting during device QA.' },
};

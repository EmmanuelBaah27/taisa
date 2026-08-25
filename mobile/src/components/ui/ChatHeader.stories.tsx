import type { Meta, StoryObj } from '@storybook/react-native';

import { ChatHeader } from './ChatHeader';

const meta: Meta<typeof ChatHeader> = {
  title: 'Patterns/ChatHeader',
  component: ChatHeader,
  args: { title: 'Conversation title', topInset: 47, onClose: () => undefined },
  argTypes: { onClose: { action: 'closed' } },
};

export default meta;
type Story = StoryObj<typeof meta>;
export const Default: Story = {};
export const AccessibilityTextScaling: Story = {
  parameters: { notes: 'Verify the title and close control at the largest device text setting during device QA.' },
};

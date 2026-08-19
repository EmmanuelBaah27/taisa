import type { Meta, StoryObj } from '@storybook/react-native';
import { TranscriptCorrectionCard } from './TranscriptCorrectionCard';

const meta: Meta<typeof TranscriptCorrectionCard> = {
  title: 'Patterns/TranscriptCorrectionCard',
  component: TranscriptCorrectionCard,
  args: {
    value: 'I led the roadmap conversation and made the trade-off clear.',
    onChangeText: () => undefined,
    onCancel: () => undefined,
    onSubmit: () => undefined,
  },
  argTypes: {
    onChangeText: { action: 'changed' },
    onCancel: { action: 'cancelled' },
    onSubmit: { action: 'submitted' },
  },
};

export default meta;
type Story = StoryObj<typeof meta>;
export const Default: Story = {};
export const Disabled: Story = { args: { disabled: true } };

import type { Meta, StoryObj } from '@storybook/react-native';
import { TaisaReplyCard } from './TaisaReplyCard';

const meta: Meta<typeof TaisaReplyCard> = {
  title: 'Patterns/TaisaReplyCard',
  component: TaisaReplyCard,
  args: { content: 'You moved the work forward and made the decision visible. What do you want to protect tomorrow?' },
};

export default meta;
type Story = StoryObj<typeof meta>;
export const Default: Story = {};
export const LongContent: Story = {
  args: { content: 'There are two useful signals here. You finished the difficult part before asking for reassurance, and you noticed that the uncertainty was about visibility rather than ability.' },
};
export const WithFeedback: Story = {
  args: { responseId: 'response-1', onReact: () => undefined, onShareExample: () => undefined },
};

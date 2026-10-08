import type { Meta, StoryObj } from '@storybook/react-native';
import { VoiceDraftStrip } from './VoiceDraftStrip';

const meta: Meta<typeof VoiceDraftStrip> = {
  title: 'Patterns/VoiceDraftStrip',
  component: VoiceDraftStrip,
  args: {
    label: 'Voice draft · 0:42',
    preview: 'I want to think through the roadmap conversation',
    onOpen: () => undefined,
    onDelete: () => undefined,
  },
  argTypes: { onOpen: { action: 'opened' }, onDelete: { action: 'deleted' } },
};

export default meta;
type Story = StoryObj<typeof meta>;
export const Default: Story = {};
export const WithoutPreview: Story = { args: { preview: undefined } };

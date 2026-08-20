import type { Meta, StoryObj } from '@storybook/react-native';
import { RecordingDiscardSheet } from './RecordingDiscardSheet';

const meta = { title: 'Patterns/RecordingDiscardSheet', component: RecordingDiscardSheet } satisfies Meta<typeof RecordingDiscardSheet>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Cancel: Story = { args: { intent: 'cancel', onGoBack: () => undefined, onConfirm: () => undefined } };
export const SwitchToKeyboard: Story = { args: { intent: 'keyboard', onGoBack: () => undefined, onConfirm: () => undefined } };

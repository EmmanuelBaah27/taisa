import type { Meta, StoryObj } from '@storybook/react-native';
import { View } from 'react-native';

import {
  BOTTOM_NAVIGATION_CAPSULE_FRAMES,
} from '../../navigation/bottomNavigation';
import { Icon } from './Icon';
import { NaviiAvatar } from './NaviiAvatar';
import { PersistentNavigationCapsule } from './PersistentNavigationCapsule';
import { colorTokens } from '../../design-system/tokens';

const meta: Meta<typeof PersistentNavigationCapsule> = {
  title: 'Components/PersistentNavigationCapsule',
  component: PersistentNavigationCapsule,
  args: {
    label: 'Home',
    leadingVisual: <Icon name="IconHomeLine" size={24} color={colorTokens.text.primary} />,
    frame: BOTTOM_NAVIGATION_CAPSULE_FRAMES.index,
    phase: 'resting',
  },
  argTypes: {
    label: { control: 'select', options: ['Home', 'Chats', 'Me'] },
    phase: { control: 'select', options: ['resting', 'travelling', 'settling'] },
    frame: { control: false },
    leadingVisual: { control: false },
  },
  decorators: [
    (Story) => (
      <View
        style={{
          width: 240,
          height: 60,
          position: 'relative',
          backgroundColor: colorTokens.surface.app,
        }}
      >
        <Story />
      </View>
    ),
  ],
};

export default meta;
type Story = StoryObj<typeof meta>;

const icon = (name: 'IconHomeLine' | 'IconChatBubbles') => (
  <Icon name={name} size={24} color={colorTokens.text.primary} />
);

export const HomeResting: Story = {
  args: {
    label: 'Home',
    leadingVisual: icon('IconHomeLine'),
    frame: BOTTOM_NAVIGATION_CAPSULE_FRAMES.index,
    phase: 'resting',
  },
};

export const ChatsTravelling: Story = {
  args: {
    label: 'Chats',
    leadingVisual: icon('IconChatBubbles'),
    frame: BOTTOM_NAVIGATION_CAPSULE_FRAMES.chats,
    phase: 'travelling',
  },
};

export const MeSettling: Story = {
  args: {
    label: 'Me',
    leadingVisual: <NaviiAvatar seed="taisa-user" size={24} />,
    frame: BOTTOM_NAVIGATION_CAPSULE_FRAMES.you,
    phase: 'settling',
  },
};

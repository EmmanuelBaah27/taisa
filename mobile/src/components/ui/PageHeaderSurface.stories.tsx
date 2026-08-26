import type { Meta, StoryObj } from '@storybook/react-native';
import { View } from 'react-native';

import { PageHeaderSurface } from './PageHeaderSurface';
import { Text } from './Text';

const meta: Meta<typeof PageHeaderSurface> = {
  title: 'Patterns/PageHeaderSurface',
  component: PageHeaderSurface,
  args: { variant: 'title' },
  render: (args) => (
    <View className="h-48 bg-background">
      <PageHeaderSurface {...args}>
        <View className="px-5 pb-3 pt-12"><Text role="heading">Chats</Text></View>
      </PageHeaderSurface>
      <View className="px-5 pt-28"><Text color="secondary">Scrolling content passes beneath the translucent header.</Text></View>
    </View>
  ),
};

export default meta;
type Story = StoryObj<typeof meta>;
export const Title: Story = {};
export const Workspace: Story = { args: { variant: 'workspace' } };

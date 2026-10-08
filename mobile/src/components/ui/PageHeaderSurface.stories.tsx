import type { Meta, StoryObj } from '@storybook/react-native';
import { Text, View } from 'react-native';

import { PageHeaderSurface } from './PageHeaderSurface';

const meta: Meta<typeof PageHeaderSurface> = {
  title: 'Patterns/PageHeaderSurface',
  component: PageHeaderSurface,
  args: { variant: 'title' },
  render: (args) => (
    <View className="h-48 bg-background">
      <PageHeaderSurface {...args}>
        <Text className="px-5 pb-3 pt-12 text-foreground text-H1">Chats</Text>
      </PageHeaderSurface>
      <Text className="px-5 pt-28 text-muted-foreground text-base-regular">
        Scrolling content passes beneath the translucent header.
      </Text>
    </View>
  ),
};

export default meta;
type Story = StoryObj<typeof meta>;
export const Title: Story = {};
export const Workspace: Story = { args: { variant: 'workspace' } };

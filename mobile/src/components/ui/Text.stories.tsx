import type { Meta, StoryObj } from '@storybook/react-native';
import { ScrollView, View } from 'react-native';

import { Text } from './Text';
import type { TextColorRole } from './Text';

const meta: Meta<typeof Text> = {
  title: 'Foundations/Text',
  component: Text,
  args: {
    children: 'Taisa helps you notice the work that matters.',
  },
};

export default meta;
type Story = StoryObj<typeof meta>;

export const Default: Story = {};

export const TypeScale: Story = {
  render: () => (
    <ScrollView className="flex-1 bg-background" contentContainerClassName="gap-4 p-5">
      <Text role="display">Display — 28px</Text>
      <Text role="heading">Heading — 24px</Text>
      <Text role="subheading">Subheading — 20px</Text>
      <Text role="body">Body — 16px readable default copy</Text>
      <Text role="bodyStrong">Body strong — 16px</Text>
      <Text role="label">Label — 14px supporting UI</Text>
      <Text role="labelStrong">Label strong — 14px</Text>
      <Text role="metadata">Metadata — 12px tertiary detail</Text>
      <Text role="metadataStrong">Metadata strong — 12px</Text>
    </ScrollView>
  ),
};

const COLOR_ROLES: TextColorRole[] = [
  'primary',
  'secondary',
  'tertiary',
  'inverted',
  'disabled',
  'success',
  'warning',
  'danger',
  'info',
];

export const Colors: Story = {
  render: () => (
    <View className="gap-3 bg-background p-5">
      {COLOR_ROLES.map((color) => (
        <View key={color} className={color === 'inverted' ? 'rounded-3 bg-foreground p-2' : ''}>
          <Text color={color}>{color}</Text>
        </View>
      ))}
    </View>
  ),
};

export const WrappingAndAccessibilityLength: Story = {
  render: () => (
    <View className="w-64 gap-3 bg-background p-5">
      <Text role="subheading">A longer section heading wraps without losing hierarchy</Text>
      <Text numberOfLines={4}>
        Taisa helps you notice the work that matters, name the pattern clearly, and choose a practical next move without shrinking readable body copy.
      </Text>
      <Text role="label" color="secondary">Supporting labels remain intentional at fourteen pixels.</Text>
      <Text role="metadata" color="tertiary">Metadata is reserved for tertiary detail.</Text>
    </View>
  ),
};

import type { Meta, StoryObj } from '@storybook/react-native';
import { Text, View } from 'react-native';
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from './Card';
import { Button } from './Button';
import { Badge } from './Badge';

const meta: Meta<typeof Card> = {
  title: 'Components/Card',
  component: Card,
  args: {
    surface: 'default',
  },
  argTypes: {
    surface: {
      control: 'select',
      options: ['default', 'elevated'],
    },
  },
  decorators: [
    (Story) => (
      <View style={{ padding: 24, backgroundColor: '#FAFAFA' }}>
        <Story />
      </View>
    ),
  ],
};

export default meta;
type Story = StoryObj<typeof meta>;

export const Default: Story = {
  render: (args) => (
    <Card {...args}>
      <CardHeader>
        <CardTitle>Today's session</CardTitle>
        <CardDescription>Tuesday 12 May · 3 mins</CardDescription>
      </CardHeader>
      <CardContent>
        <Text style={{ color: '#0F0F0F', fontSize: 15 }}>
          Finished the pitch deck and got positive feedback from the team. Feeling more confident about Thursday.
        </Text>
      </CardContent>
    </Card>
  ),
};

export const Elevated: Story = {
  args: { surface: 'elevated' },
  render: (args) => (
    <Card {...args}>
      <CardHeader>
        <CardTitle>Coaching insight</CardTitle>
        <CardDescription>From your last 7 days</CardDescription>
      </CardHeader>
      <CardContent>
        <Text style={{ color: '#737373', fontSize: 14 }}>
          You've mentioned "confidence" in 4 of your last 7 entries. That's a pattern worth exploring.
        </Text>
      </CardContent>
      <CardFooter>
        <Button variant="tertiary" size="sm" label="Explore this" />
      </CardFooter>
    </Card>
  ),
};

export const WithBadge: Story = {
  name: 'With Badge',
  render: () => (
    <Card>
      <CardHeader>
        <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
          <CardTitle>Pitch deck finalised</CardTitle>
          <Badge color="success" size="sm">Win</Badge>
        </View>
        <CardDescription>Monday 11 May</CardDescription>
      </CardHeader>
      <CardContent>
        <Text style={{ color: '#0F0F0F', fontSize: 15 }}>
          Completed the investor deck ahead of schedule. This is CV-worthy.
        </Text>
      </CardContent>
    </Card>
  ),
};

export const WithFooter: Story = {
  name: 'With Footer Actions',
  render: () => (
    <Card>
      <CardHeader>
        <CardTitle>Action item</CardTitle>
      </CardHeader>
      <CardContent>
        <Text style={{ color: '#0F0F0F', fontSize: 15 }}>
          Follow up with Sarah about the design review by Friday.
        </Text>
      </CardContent>
      <CardFooter style={{ gap: 8 }}>
        <Button variant="primary" size="sm" label="Mark done" />
        <Button variant="secondary" size="sm" label="Snooze" />
      </CardFooter>
    </Card>
  ),
};

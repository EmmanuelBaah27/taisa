import React from 'react';
import { View } from 'react-native';
import '../global.css';
import type { Preview } from '@storybook/react-native';

const preview: Preview = {
  decorators: [
    (Story) => (
      <View style={{ flex: 1, padding: 16, backgroundColor: '#FFFFFF' }}>
        <Story />
      </View>
    ),
  ],
  parameters: {
    backgrounds: {
      default: 'white',
      values: [
        { name: 'white', value: '#FFFFFF' },
        { name: 'subtle', value: '#FAFAFA' },
        { name: 'dark', value: '#0A0A0F' },
      ],
    },
    controls: {
      matchers: {
        color: /(background|color)$/i,
        date: /Date$/,
      },
    },
  },
};

export default preview;

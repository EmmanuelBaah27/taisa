import React from 'react';
import { View } from 'react-native';
import '../global.css';
import type { Preview } from '@storybook/react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { SafeAreaProvider } from 'react-native-safe-area-context';

const preview: Preview = {
  decorators: [
    (Story) => (
      <GestureHandlerRootView style={{ flex: 1 }}>
        <SafeAreaProvider>
          <View className="flex-1 bg-background p-4">
            <Story />
          </View>
        </SafeAreaProvider>
      </GestureHandlerRootView>
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

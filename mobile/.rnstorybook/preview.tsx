import React from 'react';
import { View } from 'react-native';
import '../global.css';
import type { Preview } from '@storybook/react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { colorTokens } from '../src/design-system/tokens';

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
        { name: 'white', value: colorTokens.surface.app },
        { name: 'subtle', value: colorTokens.surface.subtle },
        { name: 'dark', value: colorTokens.surface.inverted },
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

import type { Meta, StoryObj } from '@storybook/react-native';
import { Text, View } from 'react-native';

import { getLiquidGlassAppearance, type LiquidGlassHierarchy, type LiquidGlassTone } from './liquidGlass';

const TokenMatrix = () => (
  <View className="gap-3 bg-background p-6">
    {(['prominent', 'standard', 'subtle'] as LiquidGlassHierarchy[]).map((hierarchy) => (
      <View key={hierarchy} className="gap-2">
        <Text className="text-small-semibold text-foreground">{hierarchy}</Text>
        <View className="flex-row gap-2">
          {(['neutral', 'accent', 'destructive'] as LiquidGlassTone[]).map((tone) => {
            const appearance = getLiquidGlassAppearance(hierarchy, tone);
            return (
              <View
                key={tone}
                className="h-12 flex-1 items-center justify-center rounded-full border"
                style={{
                  backgroundColor: appearance.fallback.backgroundColor,
                  borderColor: appearance.fallback.borderColor,
                }}
              >
                <Text className="text-caption-medium text-foreground">{tone}</Text>
              </View>
            );
          })}
        </View>
      </View>
    ))}
  </View>
);

const meta: Meta<typeof TokenMatrix> = {
  title: 'Foundations/LiquidGlass',
  component: TokenMatrix,
};

export default meta;
type Story = StoryObj<typeof meta>;

export const SemanticMapping: Story = {};

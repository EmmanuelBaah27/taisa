import { createContext, useContext } from 'react';
import type { SharedValue } from 'react-native-reanimated';

import type { MainDestinationId } from './interactiveMainNavigation';

export interface MainNavigationInteractionValue {
  activeIndex: number;
  progress: SharedValue<number>;
  fromIndex: SharedValue<number>;
  toIndex: SharedValue<number>;
  interacting: SharedValue<number>;
  navigate(destinationId: MainDestinationId): void;
}

export const MainNavigationInteractionContext = createContext<MainNavigationInteractionValue | null>(null);

export function useMainNavigationInteraction() {
  return useContext(MainNavigationInteractionContext);
}

export function navigateWithMainNavigation(
  interaction: Pick<MainNavigationInteractionValue, 'navigate'> | null,
  destinationId: MainDestinationId,
  fallback: () => void,
): void {
  if (interaction) {
    interaction.navigate(destinationId);
    return;
  }

  fallback();
}

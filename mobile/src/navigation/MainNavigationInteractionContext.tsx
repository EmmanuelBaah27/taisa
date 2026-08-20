import { createContext, useContext } from 'react';
import type { SharedValue } from 'react-native-reanimated';

export interface MainNavigationInteractionValue {
  progress: SharedValue<number>;
  fromIndex: SharedValue<number>;
  toIndex: SharedValue<number>;
  interacting: SharedValue<number>;
}

export const MainNavigationInteractionContext = createContext<MainNavigationInteractionValue | null>(null);

export function useMainNavigationInteraction() {
  return useContext(MainNavigationInteractionContext);
}

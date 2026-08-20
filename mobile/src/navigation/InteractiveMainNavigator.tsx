import {
  createNavigatorFactory,
  type ParamListBase,
  type TabActionHelpers,
  type TabNavigationState,
  TabRouter,
  type TabRouterOptions,
  useNavigationBuilder,
} from '@react-navigation/native';
import { withLayoutContext } from 'expo-router';
import type { ComponentType } from 'react';
import { View } from 'react-native';

import { VoiceButton as DefaultVoiceButton } from '../components/VoiceButton';
import { BottomNavBar as DefaultBottomNavBar } from '../components/ui/BottomNavBar';

export type InteractiveMainNavigationOptions = Record<string, never>;

export type InteractiveMainNavigationEventMap = {
  tabPress: { data: undefined; canPreventDefault: true };
};

type InteractiveMainNavigationBuilder = ReturnType<
  typeof useNavigationBuilder<
    TabNavigationState<ParamListBase>,
    TabRouterOptions,
    TabActionHelpers<ParamListBase>,
    InteractiveMainNavigationOptions,
    InteractiveMainNavigationEventMap
  >
>;

type InteractiveMainNavigatorProps = Parameters<
  typeof useNavigationBuilder<
    TabNavigationState<ParamListBase>,
    TabRouterOptions,
    TabActionHelpers<ParamListBase>,
    InteractiveMainNavigationOptions,
    InteractiveMainNavigationEventMap
  >
>[1];

export interface InteractiveMainNavigatorViewProps {
  state: InteractiveMainNavigationBuilder['state'];
  navigation: InteractiveMainNavigationBuilder['navigation'];
  descriptors: InteractiveMainNavigationBuilder['descriptors'];
  BottomNavBar?: ComponentType;
  VoiceButton?: ComponentType;
}

export function InteractiveMainNavigatorView({
  state,
  descriptors,
  BottomNavBar = DefaultBottomNavBar,
  VoiceButton = DefaultVoiceButton,
}: InteractiveMainNavigatorViewProps) {
  const activeRoute = state.routes[state.index];
  const activeDescriptor = descriptors[activeRoute.key];

  return (
    <View className="flex-1" testID="main-navigation-shell">
      <View
        className="flex-1 overflow-hidden bg-white"
        testID="main-scene-viewport"
      >
        <View className="flex-1" testID={`main-scene-${activeRoute.name}`}>
          {activeDescriptor.render()}
        </View>
      </View>
      <BottomNavBar />
      <VoiceButton />
    </View>
  );
}

function InteractiveMainNavigatorBase({
  id,
  initialRouteName,
  children,
  screenListeners,
  screenOptions,
}: InteractiveMainNavigatorProps) {
  const { state, navigation, descriptors, NavigationContent } =
    useNavigationBuilder<
      TabNavigationState<ParamListBase>,
      TabRouterOptions,
      TabActionHelpers<ParamListBase>,
      InteractiveMainNavigationOptions,
      InteractiveMainNavigationEventMap
    >(TabRouter, {
      id,
      initialRouteName,
      children,
      screenListeners,
      screenOptions,
    });

  return (
    <NavigationContent>
      <InteractiveMainNavigatorView
        state={state}
        navigation={navigation}
        descriptors={descriptors}
      />
    </NavigationContent>
  );
}

const InteractiveMainNavigatorFactory = createNavigatorFactory(
  InteractiveMainNavigatorBase,
)();

export const InteractiveMainNavigator = withLayoutContext<
  InteractiveMainNavigationOptions,
  typeof InteractiveMainNavigatorFactory.Navigator,
  TabNavigationState<ParamListBase>,
  InteractiveMainNavigationEventMap
>(InteractiveMainNavigatorFactory.Navigator);

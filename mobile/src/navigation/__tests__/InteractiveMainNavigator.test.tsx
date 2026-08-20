import fs from 'node:fs';
import path from 'node:path';
import React from 'react';
import { View } from 'react-native';

jest.mock('../../components/VoiceButton', () => ({
  VoiceButton: () => null,
}));
jest.mock('../../components/ui/BottomNavBar', () => ({
  BottomNavBar: () => null,
}));

import {
  InteractiveMainNavigatorView,
  type InteractiveMainNavigatorViewProps,
} from '../InteractiveMainNavigator';

function findByTestId(node: React.ReactNode, testID: string): React.ReactElement | null {
  if (!React.isValidElement<{ children?: React.ReactNode; testID?: string }>(node)) {
    return null;
  }

  if (node.props.testID === testID) return node;

  for (const child of React.Children.toArray(node.props.children)) {
    const match = findByTestId(child, testID);
    if (match) return match;
  }

  return null;
}

describe('InteractiveMainNavigator', () => {
  test('renders only the route selected by router state at rest', () => {
    const routes = [
      { key: 'chats-key', name: 'chats' },
      { key: 'index-key', name: 'index' },
      { key: 'you-key', name: 'you' },
    ];
    const descriptors = Object.fromEntries(
      routes.map((route) => [
        route.key,
        {
          render: () => <View accessibilityLabel={`${route.name} content`} />,
        },
      ]),
    );

    const view = InteractiveMainNavigatorView({
      state: {
        stale: false,
        type: 'tab',
        key: 'main-tabs',
        index: 1,
        routeNames: routes.map((route) => route.name),
        history: [{ type: 'route', key: 'index-key' }],
        preloadedRouteKeys: [],
        routes,
      },
      navigation: {} as InteractiveMainNavigatorViewProps['navigation'],
      descriptors: descriptors as InteractiveMainNavigatorViewProps['descriptors'],
      BottomNavBar: () => <View testID="main-bottom-navigation" />,
      VoiceButton: () => <View testID="main-voice-button" />,
    });
    const screen = {
      getByTestId(testID: string) {
        const match = findByTestId(view, testID);
        if (!match) throw new Error(`Unable to find testID: ${testID}`);
        return match;
      },
      queryByTestId(testID: string) {
        return findByTestId(view, testID);
      },
    };

    expect(screen.getByTestId('main-scene-index')).toBeTruthy();
    expect(screen.queryByTestId('main-scene-chats')).toBeNull();
    expect(screen.queryByTestId('main-scene-you')).toBeNull();
    expect(screen.getByTestId('main-navigation-shell')).toBeTruthy();
  });

  test('uses the route-authoritative custom navigator boundary without a native pager', () => {
    const source = fs.readFileSync(
      path.resolve(__dirname, '../InteractiveMainNavigator.tsx'),
      'utf8',
    );

    expect(source).toMatch(/useNavigationBuilder<[\s\S]*?>\(TabRouter/);
    expect(source).toMatch(/withLayoutContext/);
    expect(source).not.toMatch(/react-native-pager-view/);
  });
});

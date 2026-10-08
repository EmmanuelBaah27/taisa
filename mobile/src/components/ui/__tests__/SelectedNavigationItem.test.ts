import type { ReactElement } from 'react';

import { SelectedNavigationItem } from '../SelectedNavigationItem';

describe('SelectedNavigationItem', () => {
  test('uses the loaded Inter Medium font token for its label', () => {
    const item = SelectedNavigationItem({
      label: 'Chats',
      leadingVisual: null,
      width: 108,
      onPress: jest.fn(),
    }) as ReactElement<{
      children: ReactElement<{
        children: ReactElement<{ className: string }>[];
      }>;
    }>;
    const contentRow = item.props.children;
    const label = contentRow.props.children[1] as ReactElement<{ className: string }>;

    expect(label.props.className).toContain('font-sans-medium');
  });
});

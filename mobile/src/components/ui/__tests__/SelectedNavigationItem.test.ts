import type { ReactElement } from 'react';

import { SelectedNavigationItem } from '../SelectedNavigationItem';

describe('SelectedNavigationItem', () => {
  test('uses the semantic 16px strong-body role for its label', () => {
    const item = SelectedNavigationItem({
      label: 'Chats',
      leadingVisual: null,
      width: 108,
      onPress: jest.fn(),
    }) as ReactElement<{
      children: ReactElement<{
        children: ReactElement<{ role: string }>[];
      }>;
    }>;
    const contentRow = item.props.children;
    const label = contentRow.props.children[1] as ReactElement<{ role: string }>;

    expect(label.props.role).toBe('bodyStrong');
  });
});

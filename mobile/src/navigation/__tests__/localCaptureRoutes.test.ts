import fs from 'node:fs';
import path from 'node:path';
import React from 'react';
import { router } from 'expo-router';

import { DigestCard } from '../../components/DigestCard';
import { TaisaCard } from '../../components/TaisaCard';

jest.mock('expo-router', () => ({
  router: {
    push: jest.fn(),
  },
}));

const push = router.push as jest.Mock;

describe('local-first capture navigation', () => {
  beforeEach(() => {
    push.mockClear();
  });

  test('the default Taisa card action opens local-first chat capture', () => {
    const card = TaisaCard({
      eyebrow: 'A pattern worth exploring',
      body: 'You have mentioned ownership several times.',
      cta: 'Talk it through',
    }) as React.ReactElement<{ onPress: () => void }>;

    card.props.onPress();

    expect(push).toHaveBeenCalledWith('/chat');
  });

  test('digest item actions open local-first chat capture', () => {
    const digest = DigestCard({
      headline: 'Your week',
      items: [
        {
          type: 'pattern',
          color: 'accent',
          text: 'You kept returning to stakeholder alignment.',
          cta: 'Continue',
        },
      ],
    }) as React.ReactElement<{ children: React.ReactNode }>;
    const itemAction = React.Children.toArray(digest.props.children).find(
      (child) => React.isValidElement<{ onPress?: () => void }>(child)
        && typeof child.props.onPress === 'function',
    ) as React.ReactElement<{ onPress: () => void }>;

    itemAction.props.onPress();

    expect(push).toHaveBeenCalledWith('/chat');
  });

  test('the legacy recording route is only a safe local-first compatibility redirect', () => {
    const recordingRoute = fs.readFileSync(
      path.resolve(__dirname, '../../../app/recording/index.tsx'),
      'utf8',
    );

    expect(recordingRoute).toMatch(/<Redirect\s+href=\{LOCAL_CAPTURE_ROUTE\}\s*\/>/);
    expect(recordingRoute).not.toMatch(/transcribeAudio|services\/api|api\.post/);
    expect(recordingRoute).not.toMatch(/\/entries(?:[/'"`?]|$)/);
    expect(recordingRoute).not.toMatch(/\/analyze(?:[/'"`?]|$)/);
  });
});

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

  test('a microphone start failure offers a keyboard escape instead of retry-only UI', () => {
    const chatScreen = fs.readFileSync(
      path.resolve(__dirname, '../../../app/chat/index.tsx'),
      'utf8',
    );

    expect(chatScreen).toMatch(/The microphone is unavailable/);
    expect(chatScreen).toMatch(/Use keyboard/);
    expect(chatScreen).toMatch(/setPhase\('idle'\)/);
  });

  test('the composer remains visible above the iOS keyboard and clears after a successful retry', () => {
    const chatScreen = fs.readFileSync(
      path.resolve(__dirname, '../../../app/chat/index.tsx'),
      'utf8',
    );

    expect(chatScreen).toMatch(/KeyboardAvoidingView/);
    expect(chatScreen).toMatch(/behavior=\{Platform\.OS === 'ios' \? 'padding' : undefined\}/);
    expect(chatScreen).toMatch(/await retrySubmission\(\);[\s\S]*setDraft\(''\)/);
  });

  test('completed coaching refreshes Recents immediately', () => {
    const chatScreen = fs.readFileSync(
      path.resolve(__dirname, '../../../app/chat/index.tsx'),
      'utf8',
    );
    expect(chatScreen).toMatch(/async function refreshConversation[\s\S]*fetchThread[\s\S]*fetchThreads/);
  });

  test('voice-ready follow-up requires one deliberate Reply tap and never auto-starts recording', () => {
    const chatScreen = fs.readFileSync(
      path.resolve(__dirname, '../../../app/chat/index.tsx'),
      'utf8',
    );
    const composer = fs.readFileSync(
      path.resolve(__dirname, '../../components/ui/VoiceComposer.tsx'),
      'utf8',
    );

    expect(composer).toMatch(/Reply by voice, starts recording/);
    expect(composer).toMatch(/onStartVoice/);
    expect(chatScreen).not.toMatch(/else \{\s*startListening\(\);\s*\}/);
  });

  test('a microphone failure offers a working keyboard fallback that selects text mode', () => {
    const chatScreen = fs.readFileSync(
      path.resolve(__dirname, '../../../app/chat/index.tsx'),
      'utf8',
    );

    expect(chatScreen).toMatch(/function handleUseKeyboard\(\)[\s\S]*restore-mode[\s\S]*mode: 'text'/);
    expect(chatScreen).toMatch(/function handleUseKeyboard\(\)[\s\S]*setPreferredInputMode\([^,]+, 'text'\)/);
    expect(chatScreen).toMatch(/onPress=\{handleUseKeyboard\}/);
  });

  test('deleting a retained failed voice draft abandons durable audio before clearing the local draft', () => {
    const chatScreen = fs.readFileSync(
      path.resolve(__dirname, '../../../app/chat/index.tsx'),
      'utf8',
    );

    expect(chatScreen).toMatch(/async function confirmVoiceDraftDeletion\(\)[\s\S]*await abandonVoiceSubmission\(requestId\)[\s\S]*setPendingRecording\(null\)[\s\S]*confirm-delete-voice/);
    expect(chatScreen).toMatch(/confirmVoiceDraftDeletion\(\)\.catch/);
  });

  test('transcript correction is rendered by a typed design-system component', () => {
    const chatScreen = fs.readFileSync(
      path.resolve(__dirname, '../../../app/chat/index.tsx'),
      'utf8',
    );
    const index = fs.readFileSync(
      path.resolve(__dirname, '../../components/ui/index.ts'),
      'utf8',
    );

    expect(chatScreen).toMatch(/TranscriptCorrectionCard/);
    expect(index).toMatch(/export \{ TranscriptCorrectionCard \}/);
  });

  test('every remaining form surface declares iOS keyboard avoidance', () => {
    const files = [
      '../../../app/onboarding/index.tsx',
      '../../../app/(tabs)/you.tsx',
      '../../../app/thread/[id].tsx',
      '../../../app/chat/index.tsx',
    ];
    for (const file of files) {
      const source = fs.readFileSync(path.resolve(__dirname, file), 'utf8');
      expect(source).toMatch(/KeyboardAvoidingView/);
    }
  });

  test('backup passphrases can be revealed deliberately and are never presented as recoverable', () => {
    const youScreen = fs.readFileSync(
      path.resolve(__dirname, '../../../app/(tabs)/you.tsx'),
      'utf8',
    );
    expect(youScreen).toMatch(/Show passphrase/);
    expect(youScreen).toMatch(/Hide passphrase/);
    expect(youScreen).toMatch(/secureTextEntry=\{!passphraseVisible\}/);
    expect(youScreen).toMatch(/Taisa does not save this passphrase and cannot recover it/);
  });
});

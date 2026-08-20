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

  test('the composer uses waveform voice entry outside the text field and restricts failed voice recovery', () => {
    const composer = fs.readFileSync(
      path.resolve(__dirname, '../../components/ui/VoiceComposer.tsx'),
      'utf8',
    );
    const chat = fs.readFileSync(path.resolve(__dirname, '../../../app/chat/index.tsx'), 'utf8');

    expect(composer).not.toMatch(/IconMicrophone/);
    expect(composer).toMatch(/IconVoiceMid/);
    const surfaces = fs.readFileSync(
      path.resolve(__dirname, '../../components/ui/ChatSurfaces.tsx'),
      'utf8',
    );
    expect(surfaces).toMatch(/Discard recording/);
    expect(composer).toMatch(/Resume/);
    expect(chat).toMatch(/submissionFailed/);
    expect(chat).toMatch(/pendingRecording\?\.durationSeconds \?\? recorder\.duration/);
    expect(chat).toMatch(/hydrated\.activeRequestStatus === 'transcription-failed'/);
    expect(chat).toMatch(/if \(activeRequestId === null\)/);
    expect(chat).toMatch(/pendingRecordingRef\.current !== null\) await handleComposerSend/);
    expect(chat).toMatch(/requestDestructiveInput\('discard-voice-submission', confirmVoiceDraftDeletion\)/);
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

  test('historical chat waits for its reverse morph while non-card exits stay immediate', () => {
    const chatScreen = fs.readFileSync(
      path.resolve(__dirname, '../../../app/chat/index.tsx'),
      'utf8',
    );
    const rootLayout = fs.readFileSync(
      path.resolve(__dirname, '../../../app/_layout.tsx'),
      'utf8',
    );

    expect(chatScreen).toMatch(/Gesture\.Pan/);
    expect(chatScreen).toMatch(/onScrollAtTopChange/);
    expect(chatScreen).toMatch(/shouldDismissChatSheet/);
    expect(chatScreen).toMatch(/getResistedChatSheetTranslation\(event\.translationY\)/);
    expect(chatScreen).toMatch(/CHAT_SHEET_DISMISS_DURATION/);
    expect(chatScreen).toMatch(/if \(hasDestructiveVoiceInput\)[\s\S]*withSpring\(0, CHAT_SHEET_RETURN_SPRING[\s\S]*handleGestureDestructiveClose/);
    expect(chatScreen).toMatch(/handleGestureDestructiveClose[\s\S]*requestDestructiveInput\('cancel-recording'/);
    expect(chatScreen).toMatch(/<GestureDetector[\s\S]*<View\s+collapsable=\{false\}[\s\S]*<ChatScreenShell/);
    expect(chatScreen).toMatch(/close\(commitClose\)/);
    expect(chatScreen).toMatch(/if \(sourceSnapshot === null\)[\s\S]*withTiming\([\s\S]*CHAT_SHEET_DISMISS_DURATION[\s\S]*runOnJS\(commitClose\)/);
    expect(chatScreen).toMatch(/if \(sourceSnapshot === null\) await fetchThreads\(\)/);
    expect(rootLayout).not.toMatch(/slide_from_bottom/);
    expect(rootLayout).toMatch(/name="chat\/index"[\s\S]*presentation: 'transparentModal'[\s\S]*animation: 'none'[\s\S]*backgroundColor: 'transparent'/);
  });

  test('fresh voice capture stays inside the canonical Taisa shell with existing lifecycle handlers', () => {
    const chatScreen = fs.readFileSync(
      path.resolve(__dirname, '../../../app/chat/index.tsx'),
      'utf8',
    );

    expect(chatScreen).not.toMatch(/if \(showActiveRecordingSurface\)[\s\S]*return \(/);
    expect(chatScreen).toMatch(/<ChatScreenShell[\s\S]*title="Taisa"/);
    expect(chatScreen.match(/<ChatScreenShell/g)).toHaveLength(1);
    expect(chatScreen).toMatch(/showActiveRecordingSurface[\s\S]*<ActiveRecordingContent/);
    expect(chatScreen).toMatch(/showActiveRecordingSurface[\s\S]*<ActiveRecordingActionBar/);
    expect(chatScreen).toMatch(/if \(!showActiveRecordingSurface\) return;[\s\S]*requestAnimationFrame\(revealContent\);[\s\S]*\[showActiveRecordingSurface\]/);
    expect(chatScreen).not.toMatch(/title="New chat"/);
    expect(chatScreen).toMatch(/messages\.length === 0[\s\S]*composer\.voice === 'recording'[\s\S]*composer\.voice === 'paused'/);
    expect(chatScreen).toMatch(/onClose=\{handleClose\}/);
    expect(chatScreen).toMatch(/cancelLabel=\{voiceCancelAccessibilityLabel\(initialConversationIdRef\.current\)\}/);
    expect(chatScreen).toMatch(/<VoiceComposer[\s\S]*cancelVoiceLabel=\{voiceCancelAccessibilityLabel\(initialConversationIdRef\.current\)\}/);
    expect(chatScreen).toContain("requestDestructiveInput('cancel-recording'");
    expect(chatScreen).toContain("requestDestructiveInput('switch-to-keyboard'");
    expect(chatScreen).toContain("requestDestructiveInput('delete-voice-draft'");
    expect(chatScreen).toContain("requestDestructiveInput('discard-voice-submission'");
    expect(chatScreen).not.toContain('<RecordingDiscardSheet');
    expect(chatScreen).toMatch(/bottomInset=\{keyboardVisible \? 0 : insets\.bottom\}/);
    expect(chatScreen).toMatch(/Keyboard\.scheduleLayoutAnimation\(event\)/);
    expect(chatScreen).toMatch(/Couldn’t pause recording/);
    expect(chatScreen).toMatch(/onPauseResume=\{[\s\S]*handleResumeVoice[\s\S]*handlePauseVoice/);
    expect(chatScreen).toMatch(/onSend=\{\(\) => \{ void handleComposerSend\(\); \}\}/);

    const dockStart = chatScreen.indexOf('<ChatComposerDock');
    const recordingActionBarStart = chatScreen.indexOf('<ActiveRecordingActionBar');
    const dockEnd = chatScreen.indexOf('</ChatComposerDock>', dockStart);
    expect(recordingActionBarStart).toBeGreaterThan(dockStart);
    expect(recordingActionBarStart).toBeLessThan(dockEnd);
  });

  test('recording controls stay inert until native recorder acquisition completes', () => {
    const chatScreen = fs.readFileSync(
      path.resolve(__dirname, '../../../app/chat/index.tsx'),
      'utf8',
    );

    expect(chatScreen).toMatch(/const recorderAcquiring = isRecorderAcquiring\([\s\S]*composer\.voice[\s\S]*pendingRecording[\s\S]*recorder\.isRecording/);
    expect(chatScreen).toMatch(/recordingActionDisabled=\{recorderAcquiring\}/);
    expect(chatScreen).toMatch(/async function handleComposerSend\(\) \{[\s\S]*if \(recorderAcquiring\) return;[\s\S]*dispatchComposer\(\{ type: 'send' \}\)/);
    expect(chatScreen).toMatch(/async function handlePauseVoice\(\) \{[\s\S]*if \(recorderAcquiring\) return;/);
  });

  test('a microphone start failure closes the active recording process', () => {
    const chatScreen = fs.readFileSync(
      path.resolve(__dirname, '../../../app/chat/index.tsx'),
      'utf8',
    );
    expect(chatScreen).toMatch(/catch \{[\s\S]*recordingStartGuardRef\.current\.complete\(startAttempt\)[\s\S]*await handleCancelVoice\(\)/);
  });

  test('voice cancellation preserves reply and close destinations through recorder cleanup', () => {
    const chatScreen = fs.readFileSync(
      path.resolve(__dirname, '../../../app/chat/index.tsx'),
      'utf8',
    );

    expect(chatScreen).toMatch(/voiceCancelDestination\([^)]+\) === 'close'[\s\S]*performClose\(\)/);
    expect(chatScreen).toMatch(/setPhase\('idle'\)[\s\S]*restore-mode/);
  });

  test('the composer remains visible above the iOS keyboard and clears after a successful retry', () => {
    const chatScreen = fs.readFileSync(
      path.resolve(__dirname, '../../../app/chat/index.tsx'),
      'utf8',
    );
    const chatSurfaces = fs.readFileSync(
      path.resolve(__dirname, '../../components/ui/ChatSurfaces.tsx'),
      'utf8',
    );
    const rootLayout = fs.readFileSync(
      path.resolve(__dirname, '../../../app/_layout.tsx'),
      'utf8',
    );

    expect(chatSurfaces).toMatch(/KeyboardAvoidingView/);
    expect(chatSurfaces).toMatch(/KeyboardAvoidingView[\s\S]*className="flex-1 bg-background"/);
    expect(chatSurfaces).toMatch(/behavior=\{Platform\.OS === 'ios' \? 'padding' : undefined\}/);
    expect(rootLayout).toMatch(/name="chat\/index"[\s\S]*presentation: 'transparentModal'[\s\S]*backgroundColor: 'transparent'/);
    expect(chatScreen).toMatch(/await retrySubmission\(\);[\s\S]*setDraft\(''\)/);
  });

  test('completed coaching refreshes Recents immediately', () => {
    const chatScreen = fs.readFileSync(
      path.resolve(__dirname, '../../../app/chat/index.tsx'),
      'utf8',
    );
    expect(chatScreen).toMatch(/async function refreshConversation[\s\S]*fetchThread[\s\S]*fetchThreads/);
  });

  test('transcript revision refresh stays owned by the conversation that started it', () => {
    const chatScreen = fs.readFileSync(
      path.resolve(__dirname, '../../../app/chat/index.tsx'),
      'utf8',
    );
    expect(chatScreen).toMatch(/revisionConversationId[\s\S]*sessionIdRef\.current === revisionConversationId[\s\S]*refreshConversation/);
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

  test('the global recorder opens as an Expo Router screen instead of mounting a route component manually', () => {
    const voiceButton = fs.readFileSync(
      path.resolve(__dirname, '../../components/VoiceButton.tsx'),
      'utf8',
    );
    const tabLayout = fs.readFileSync(
      path.resolve(__dirname, '../../../app/(tabs)/_layout.tsx'),
      'utf8',
    );

    expect(voiceButton).toMatch(/router\.push\('\/chat'\)/);
    expect(tabLayout).not.toMatch(/import ChatScreen/);
    expect(tabLayout).not.toMatch(/<ChatScreen/);
  });

  test('main tabs use the route-authoritative navigator without a hand-written horizontal gesture', () => {
    const tabLayout = fs.readFileSync(
      path.resolve(__dirname, '../../../app/(tabs)/_layout.tsx'),
      'utf8',
    );
    const mainNavigator = fs.readFileSync(
      path.resolve(__dirname, '../InteractiveMainNavigator.tsx'),
      'utf8',
    );

    expect(tabLayout).not.toMatch(/pageTranslateX|pageSwipeGesture|exitX/);
    expect(tabLayout).toMatch(/backgroundColor: PAGE_TRANSITION\.backdropColor/);
    expect(tabLayout).toMatch(/<InteractiveMainNavigator initialRouteName=\{CURRENT_INITIAL_TAB\}>/);
    expect(tabLayout).toMatch(/<InteractiveMainNavigator\.Screen name="chats" \/>[\s\S]*name="index"[\s\S]*name="you"/);
    expect(tabLayout).not.toMatch(/name="logs"|name="insights"|name="goals"/);
    expect(mainNavigator).toMatch(/useNavigationBuilder<[\s\S]*?>\(TabRouter/);
    expect(mainNavigator).toMatch(/withLayoutContext/);
    expect(mainNavigator).not.toMatch(/from 'react-native-pager-view'/);
    expect(mainNavigator).toMatch(/<Animated\.ScrollView/);
    expect(mainNavigator).toMatch(/<\/Animated\.ScrollView>\s*<BottomNavBar \/>\s*<VoiceButton \/>/);
  });

  test('a microphone failure offers a working keyboard fallback that selects text mode', () => {
    const chatScreen = fs.readFileSync(
      path.resolve(__dirname, '../../../app/chat/index.tsx'),
      'utf8',
    );

    expect(chatScreen).toMatch(/function handleUseKeyboard\(\)[\s\S]*restore-mode[\s\S]*mode: 'text'/);
    expect(chatScreen).toMatch(/function handleUseKeyboard\(\)[\s\S]*setPreferredInputMode\([^,]+, 'text'\)/);
    expect(chatScreen).toMatch(/onUseKeyboard=\{handleUseKeyboard\}/);
  });

  test('deleting a retained failed voice draft abandons durable audio before clearing the local draft', () => {
    const chatScreen = fs.readFileSync(
      path.resolve(__dirname, '../../../app/chat/index.tsx'),
      'utf8',
    );

    expect(chatScreen).toMatch(/async function confirmVoiceDraftDeletion\(\)[\s\S]*canAbandonVoiceSubmission\([\s\S]*await abandonVoiceSubmission\(requestId\)[\s\S]*setPendingRecording\(null\)[\s\S]*confirm-delete-voice/);
    expect(chatScreen).toMatch(/requestDestructiveInput\('delete-voice-draft', confirmVoiceDraftDeletion\)[\s\S]*cancel-delete-voice/);
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

    expect(chatScreen).toMatch(/ChatConversationSurface/);
    expect(index).toMatch(/ChatConversationSurface/);
    expect(index).toMatch(/export \{ TranscriptCorrectionCard \}/);
  });

  test('every remaining form surface declares iOS keyboard avoidance', () => {
    const files = [
      '../../../app/onboarding/index.tsx',
      '../../../app/(tabs)/you.tsx',
      '../../../app/thread/[id].tsx',
      '../../components/ui/ChatSurfaces.tsx',
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

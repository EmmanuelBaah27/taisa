# Transcription Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the chat screen capture voice via record→Whisper (the journal screen's proven path) and remove the `expo-speech-recognition` native module entirely.

**Architecture:** Replace the live on-device transcription in `chat/index.tsx` with the existing `useVoiceRecorder` hook + `transcribeAudio` service. The chat becomes explicit tap-to-Stop: record → stop → transcribe → submit. Then delete the now-dead live-transcription hook/component and strip the native module from `package.json` + `app.json`, re-declaring iOS mic permission (currently supplied by the removed plugin). Finally regenerate the native iOS project so the speech pod is dropped.

**Tech Stack:** React Native (Expo SDK 54, managed + dev build), expo-av (recording + metering), OpenAI Whisper (server `/transcribe`), react-native-reanimated, NativeWind.

**Testing note:** This codebase has no unit-test harness for screens (prior plans verify via `npx tsc --noEmit` + manual app runs). This plan follows that established pattern: type-check + grep + a manual end-to-end checklist. No jest is introduced.

**Ordering note:** Tasks are ordered so the project compiles after every task. The chat screen is rewired off the live hook (Task 1) *before* the hook is deleted (Task 2) and *before* the package is removed (Task 3).

---

## File Structure

| Action | Path | Responsibility |
|---|---|---|
| Modify | `mobile/app/chat/index.tsx` | Voice capture via `useVoiceRecorder` + `transcribeAudio`; tap-to-Stop turn loop; `transcribing` phase; glow from `recorder.amplitude` |
| Delete | `mobile/src/hooks/useLiveTranscription.ts` | Dead after Task 1 |
| Delete | `mobile/src/components/ui/LiveTranscriptionText.tsx` | Dead after Task 1 (chat was its only consumer) |
| Modify | `mobile/src/components/ui/index.ts` | Drop `LiveTranscriptionText` exports |
| Modify | `mobile/package.json` | Remove `expo-speech-recognition` dependency |
| Modify | `mobile/app.json` | Remove speech plugin; add `ios.infoPlist.NSMicrophoneUsageDescription` |
| Native | `mobile/ios/` (regenerated) | `prebuild` + `pod install` drop the speech pod, apply mic permission |

---

## Task 1: Rewire chat screen to record → Whisper

**Files:**
- Modify: `mobile/app/chat/index.tsx`

- [ ] **Step 1: Replace the entire file with this content**

```tsx
import { useEffect, useRef, useState } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  useWindowDimensions,
} from 'react-native';
import { ScrollView } from 'react-native-gesture-handler';
import { LinearGradient } from 'expo-linear-gradient';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Animated, { useAnimatedStyle, useSharedValue, withSpring, withTiming, runOnJS } from 'react-native-reanimated';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import { useVoiceRecorder } from '../../src/hooks/useVoiceRecorder';
import { transcribeAudio } from '../../src/services/transcription';
import { useMorphTransition } from '../../src/hooks/useMorphTransition';
import { useChatStore } from '../../src/stores/chatStore';
import { useUIStore } from '../../src/stores/uiStore';
import {
  ChatNavBar,
  RecordingGlow,
  TaisaReplyCard,
  Icon,
} from '../../src/components/ui';
import api from '../../src/services/api';
import type { ChatMessage } from '../../src/stores/threadStore';

const BACKGROUND_HEX = '#ffffff';
const BACKGROUND_TRANSPARENT = 'rgba(255,255,255,0)';

const DISMISS_VELOCITY = 800;
const SPRING_BACK = { damping: 26, stiffness: 200 };

type ChatPhase = 'idle' | 'listening' | 'transcribing' | 'processing' | 'responded' | 'error';

export default function ChatScreen() {
  const insets = useSafeAreaInsets();
  const { height: screenH } = useWindowDimensions();
  const { activeSessionId, setActiveSessionId } = useChatStore();
  const { setChatMorphing } = useUIStore();
  const { translateY, open, close } = useMorphTransition();

  const slideStyle = useAnimatedStyle(() => ({
    flex: 1,
    transform: [{ translateY: translateY.value }],
  }));

  const sessionIdRef = useRef<string | null>(activeSessionId);
  const [phase, setPhase] = useState<ChatPhase>('idle');
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [error, setError] = useState<string | null>(null);
  const scrollRef = useRef<ScrollView>(null);
  const restartTimerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const closingRef = useRef(false);

  const recorder = useVoiceRecorder();

  // Stop any in-flight recording without throwing when none is active.
  const stopRecorderSafe = () => recorder.stop().catch(() => {});

  useEffect(() => {
    if (messages.length > 0) {
      setTimeout(() => scrollRef.current?.scrollToEnd({ animated: true }), 100);
    }
  }, [messages.length]);

  useEffect(() => {
    open();
    if (activeSessionId) {
      loadSession(activeSessionId);
    } else {
      startListening();
    }
    return () => {
      clearTimeout(restartTimerRef.current);
      stopRecorderSafe();
      setChatMorphing(false);
    };
  }, []);

  // ─── Drag-to-dismiss ────────────────────────────────────────────────────────

  const scrollAtTop = useSharedValue(true);
  const isHandlingDrag = useSharedValue(false);

  function commitClose(delay: number) {
    if (closingRef.current) return;
    closingRef.current = true;
    clearTimeout(restartTimerRef.current);
    stopRecorderSafe();
    restartTimerRef.current = setTimeout(() => setChatMorphing(false), delay);
  }

  const gestureCommitClose = () => commitClose(300);

  const dragGesture = Gesture.Pan()
    .activeOffsetY([5, Infinity])
    .onBegin(() => {
      isHandlingDrag.value = scrollAtTop.value;
    })
    .onUpdate((e) => {
      if (!isHandlingDrag.value || e.translationY <= 0) return;
      translateY.value = e.translationY;
    })
    .onEnd((e) => {
      if (!isHandlingDrag.value) return;
      const dismiss = e.translationY > screenH * 0.3 || e.velocityY > DISMISS_VELOCITY;
      if (dismiss) {
        translateY.value = withTiming(screenH, { duration: 280 });
        runOnJS(gestureCommitClose)();
      } else {
        translateY.value = withSpring(0, SPRING_BACK);
      }
    });

  // ─── Data & voice ───────────────────────────────────────────────────────────

  async function loadSession(sessionId: string) {
    try {
      const res = await api.get(`/chat/session/${sessionId}`);
      const loaded: ChatMessage[] = res.data.data.messages ?? [];
      setMessages(loaded);
    } catch {
      // Proceed fresh.
    }
    restartTimerRef.current = setTimeout(startListening, 2000);
  }

  async function startListening() {
    setError(null);
    setPhase('listening');
    try {
      await recorder.start();
    } catch {
      setError('Microphone permission denied. Please allow access in Settings.');
      setPhase('error');
    }
  }

  // Stop recording, transcribe with Whisper, then submit the text.
  async function handleStop() {
    if (!recorder.isRecording) return;
    setPhase('transcribing');
    try {
      const result = await recorder.stop();
      const text = await transcribeAudio(result.uri, result.durationSeconds);
      if (text.trim()) {
        await handleSubmit(text);
      } else {
        startListening();
      }
    } catch (e: any) {
      setError(e.message ?? 'Could not transcribe. Tap to retry.');
      setPhase('error');
    }
  }

  // Recording is already stopped by the time we get here.
  async function handleSubmit(text: string) {
    const trimmed = text.trim();
    if (!trimmed) return;

    setPhase('processing');

    try {
      let reply: string;

      if (sessionIdRef.current) {
        const res = await api.post('/chat/message', {
          sessionId: sessionIdRef.current,
          message: trimmed,
        });
        reply = res.data.data.reply;
      } else {
        const entryRes = await api.post('/entries', {
          rawTranscript: trimmed,
          editedTranscript: trimmed,
          audioDurationSeconds: 0,
          recordedAt: new Date().toISOString(),
          inputType: 'voice',
        });
        const entryId: string = entryRes.data.data.id;

        const analyzeRes = await api.post(`/analyze/${entryId}`);
        const sid: string = analyzeRes.data.data.sessionId;

        const sessionRes = await api.get(`/chat/session/${sid}`);
        const sessionMessages: ChatMessage[] = sessionRes.data.data.messages ?? [];
        const assistantMsg = sessionMessages.find(m => m.role === 'assistant');
        if (!assistantMsg?.content) throw new Error('No assistant reply in session');
        reply = assistantMsg.content;

        sessionIdRef.current = sid;
        setActiveSessionId(sid);
      }

      const now = new Date().toISOString();
      setMessages(prev => [
        ...prev,
        { id: `u-${Date.now()}`, role: 'user', content: trimmed, created_at: now },
        { id: `a-${Date.now()}`, role: 'assistant', content: reply, created_at: now },
      ]);

      setPhase('responded');
      restartTimerRef.current = setTimeout(startListening, 2000);
    } catch (e: any) {
      setError(e.message ?? 'Something went wrong. Tap to retry.');
      setPhase('error');
    }
  }

  function handleRetry() {
    setError(null);
    startListening();
  }

  function handleClose() {
    if (closingRef.current) return;
    close();
    commitClose(340);
  }

  return (
    <GestureDetector gesture={dragGesture}>
      <Animated.View style={[{ flex: 1, backgroundColor: '#ffffff' }, slideStyle]}>
        {/* Drag handle */}
        <View style={{ alignItems: 'center', paddingTop: insets.top + 6 }}>
          <View style={{ width: 36, height: 4, borderRadius: 2, backgroundColor: '#d8d8d8' }} />
        </View>

        <ChatNavBar onClose={handleClose} />

        <View style={{ flex: 1 }}>
          <ScrollView
            ref={scrollRef}
            style={{ flex: 1 }}
            contentContainerStyle={{ paddingHorizontal: 16, paddingBottom: 24 }}
            showsVerticalScrollIndicator={false}
            onScroll={(e) => { scrollAtTop.value = e.nativeEvent.contentOffset.y <= 2; }}
            scrollEventThrottle={16}
          >
            {messages.map(msg =>
              msg.role === 'assistant' ? (
                <TaisaReplyCard key={msg.id} content={msg.content} />
              ) : (
                <View
                  key={msg.id}
                  className="self-end mb-3 bg-lime-100 rounded-3 px-4 py-3 max-w-xs"
                >
                  <Text className="text-foreground text-base-regular">{msg.content}</Text>
                </View>
              )
            )}

            {phase === 'processing' && (
              <View className="items-start mb-3">
                <View className="bg-subtle rounded-3 px-4 py-3">
                  <Text className="text-text-tertiary text-small-regular">Taisa is thinking…</Text>
                </View>
              </View>
            )}

            {phase === 'error' && (
              <View className="items-center py-4">
                <Text className="text-danger text-small-regular mb-3 text-center">{error}</Text>
                <TouchableOpacity onPress={handleRetry} className="bg-muted rounded-full px-6 py-3">
                  <Text className="text-foreground text-small-semibold">Try again</Text>
                </TouchableOpacity>
              </View>
            )}
          </ScrollView>

          <LinearGradient
            colors={[BACKGROUND_TRANSPARENT, BACKGROUND_HEX]}
            style={{ position: 'absolute', bottom: 0, left: 0, right: 0, height: 48, pointerEvents: 'none' }}
          />
        </View>

        <RecordingGlow amplitude={recorder.amplitude} visible={phase === 'listening'} />

        {phase === 'listening' && (
          <View style={{ height: 200 }}>
            <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
              <Text className="text-text-tertiary text-small-regular">Listening…</Text>
            </View>
            <View
              className="flex-row items-center justify-between px-5"
              style={{ paddingBottom: insets.bottom + 12 }}
            >
              <View className="w-10 h-10 rounded-full border border-border items-center justify-center opacity-40">
                <Icon name="IconKeyboard" size={20} color="#898989" />
              </View>
              <TouchableOpacity
                onPress={handleStop}
                className="flex-row items-center gap-2 bg-background border border-border rounded-full px-4 py-2"
              >
                <Icon name="IconStopCircle" size={18} color="#060707" />
                <Text className="text-foreground text-small-semibold">Stop</Text>
              </TouchableOpacity>
            </View>
          </View>
        )}

        {phase === 'transcribing' && (
          <View style={{ height: 200, alignItems: 'center', justifyContent: 'center', paddingBottom: insets.bottom + 12 }}>
            <Text className="text-text-tertiary text-small-regular">Transcribing…</Text>
          </View>
        )}
      </Animated.View>
    </GestureDetector>
  );
}
```

- [ ] **Step 2: Verify chat screen type-checks (live hook no longer referenced)**

Run from `mobile/`:
```bash
npx tsc --noEmit 2>&1 | grep "chat/index" || echo "chat/index CLEAN"
```
Expected: `chat/index CLEAN`

- [ ] **Step 3: Confirm chat no longer imports the live path**

Run from `mobile/`:
```bash
grep -nE "useLiveTranscription|LiveTranscriptionText|recognizerError|amplitudeSV" app/chat/index.tsx || echo "no live-transcription references"
```
Expected: `no live-transcription references`

- [ ] **Step 4: Commit**

```bash
git add mobile/app/chat/index.tsx
git commit -m "feat(chat): capture voice via record→Whisper instead of live on-device STT"
```

---

## Task 2: Delete the dead live-transcription hook and component

**Files:**
- Delete: `mobile/src/hooks/useLiveTranscription.ts`
- Delete: `mobile/src/components/ui/LiveTranscriptionText.tsx`
- Modify: `mobile/src/components/ui/index.ts`

- [ ] **Step 1: Confirm nothing else imports them**

Run from `mobile/`:
```bash
grep -rn "useLiveTranscription\|LiveTranscriptionText" src app | grep -vE "useLiveTranscription\.ts|LiveTranscriptionText\.tsx|components/ui/index\.ts"
```
Expected: no output (only the files themselves and the barrel export remain).

- [ ] **Step 2: Delete the two files**

```bash
git rm mobile/src/hooks/useLiveTranscription.ts mobile/src/components/ui/LiveTranscriptionText.tsx
```

- [ ] **Step 3: Remove the barrel exports**

In `mobile/src/components/ui/index.ts`, delete these two lines:

```typescript
export { LiveTranscriptionText } from './LiveTranscriptionText';
export type { LiveTranscriptionTextProps } from './LiveTranscriptionText';
```

- [ ] **Step 4: Verify the whole mobile project type-checks**

Run from `mobile/`:
```bash
npx tsc --noEmit 2>&1 | grep -E "LiveTranscription|chat/index" || echo "CLEAN"
```
Expected: `CLEAN`

- [ ] **Step 5: Commit**

```bash
git add mobile/src/components/ui/index.ts
git commit -m "chore: delete dead useLiveTranscription hook and LiveTranscriptionText component"
```

---

## Task 3: Remove the native module and re-declare mic permission

**Files:**
- Modify: `mobile/package.json`
- Modify: `mobile/app.json`

- [ ] **Step 1: Remove the dependency from `mobile/package.json`**

Delete this line from the `dependencies` block:

```json
    "expo-speech-recognition": "^3.1.3",
```

- [ ] **Step 2: Update `mobile/app.json` — drop the plugin, add mic permission to infoPlist**

Replace the `ios` block:

```json
    "ios": {
      "supportsTablet": true,
      "bundleIdentifier": "com.taisa.app"
    },
```

with (adds `infoPlist` with the mic usage string that the removed plugin used to provide):

```json
    "ios": {
      "supportsTablet": true,
      "bundleIdentifier": "com.taisa.app",
      "infoPlist": {
        "NSMicrophoneUsageDescription": "Allow Taisa to access the microphone to record your voice."
      }
    },
```

Then replace the entire `plugins` array:

```json
    "plugins": [
      "expo-router",
      "expo-font",
      [
        "expo-speech-recognition",
        {
          "microphonePermission": "Allow Taisa to access the microphone to record your voice.",
          "speechRecognitionPermission": "Allow Taisa to use speech recognition to transcribe what you say."
        }
      ]
    ]
```

with:

```json
    "plugins": [
      "expo-router",
      "expo-font"
    ]
```

- [ ] **Step 3: Reinstall to update the lockfile**

Run from `mobile/`:
```bash
npm install
```
Expected: completes; `expo-speech-recognition` removed from `node_modules` and `package-lock.json`.

- [ ] **Step 4: Confirm the module is fully gone from source + manifest**

Run from `mobile/`:
```bash
grep -rn "expo-speech-recognition\|ExpoSpeechRecognition" package.json app.json src app && echo "STILL PRESENT" || echo "fully removed"
```
Expected: `fully removed`

- [ ] **Step 5: Verify type-check still clean**

Run from `mobile/`:
```bash
npx tsc --noEmit 2>&1 | grep -E "chat/index|speech|Speech" || echo "CLEAN"
```
Expected: `CLEAN`

- [ ] **Step 6: Commit**

```bash
git add mobile/package.json mobile/app.json mobile/package-lock.json
git commit -m "chore: remove expo-speech-recognition, declare mic permission via infoPlist"
```

---

## Task 4: Regenerate native iOS build and verify end-to-end

**Files:**
- Native: `mobile/ios/` (regenerated by prebuild)

**Note:** If `mobile/ios/` is gitignored (typical for Expo managed projects), the regenerated files are not committed — this task is a local build + manual verification only. Check with `git check-ignore mobile/ios` before attempting to commit native files.

- [ ] **Step 1: Regenerate the native iOS project from the updated config**

Run from `mobile/`:
```bash
npx expo prebuild --platform ios
```
Expected: completes; `ios/` regenerated with `NSMicrophoneUsageDescription` in `Info.plist` and no speech-recognition references.

- [ ] **Step 2: Confirm the speech pod is gone and mic permission present**

Run from `mobile/`:
```bash
grep -i "speech" ios/Podfile.lock 2>/dev/null && echo "SPEECH POD STILL PRESENT" || echo "speech pod removed"
grep -A1 "NSMicrophoneUsageDescription" ios/*/Info.plist 2>/dev/null || echo "WARN: check Info.plist mic permission manually"
```
Expected: `speech pod removed`, and the mic usage string present in `Info.plist`.

- [ ] **Step 3: Install pods**

Run from `mobile/ios/`:
```bash
pod install
```
Expected: completes; `ExpoSpeechRecognition` absent from the installed pods.

- [ ] **Step 4: Build and launch on the iOS Simulator**

Run from `mobile/`:
```bash
npx expo run:ios
```
Expected: app builds and launches without the "Cannot find native module ExpoSpeechRecognition" error.

- [ ] **Step 5: Manual end-to-end verification**

In the running app, open the chat screen and confirm:

- On entry, phase goes to **Listening…** and the glow animates with your voice (amplitude metering path).
- Tapping **Stop** shows **Transcribing…**, then the user message bubble appears with the Whisper transcript.
- Taisa's reply card renders; the loop returns to **Listening…** after ~2s.
- iOS shows the microphone permission prompt on first record (permission string intact).
- Existing-session path (open a saved session) loads messages, then resumes listening.
- Drag-down and the nav-bar close both dismiss cleanly and stop the recorder (no orphaned recording / no crash).

- [ ] **Step 6: Commit native changes only if `ios/` is tracked**

```bash
git check-ignore mobile/ios >/dev/null && echo "ios/ is gitignored — nothing to commit" || (git add mobile/ios && git commit -m "chore(ios): regenerate native project without speech-recognition")
```

---

## Verification (whole feature)

- [ ] `grep -rn "expo-speech-recognition\|ExpoSpeechRecognition\|useLiveTranscription\|LiveTranscriptionText" mobile/src mobile/app mobile/package.json mobile/app.json` returns nothing.
- [ ] `npx tsc --noEmit` (from `mobile/`) is clean.
- [ ] Chat records, transcribes via Whisper, and shows the agent reply on a device/simulator dev build.
- [ ] Mic permission prompt still appears; glow still animates while recording.

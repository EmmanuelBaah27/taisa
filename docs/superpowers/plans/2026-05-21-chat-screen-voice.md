# Chat Screen — Voice Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the full-screen voice chat modal that replaces the current recording bottom sheet — auto-listens, live-transcribes, auto-submits on 5s silence, shows Taisa's response, and persists the session so the VoiceButton reopens the same conversation.

**Architecture:** The VoiceButton pushes to `/chat`, a full-screen white modal. The screen auto-starts listening on mount. `@react-native-voice/voice` drives live transcription and amplitude. A 5s silence timer auto-submits the transcript — first turn creates a journal entry + calls `/analyze`, subsequent turns call `/chat/message` on the same session. The session ID is stored in `chatStore` so reopening the modal continues the conversation.

**Tech Stack:** `@react-native-voice/voice`, `expo-linear-gradient` (already installed), Expo Router, Zustand, React Native `Animated` API, NativeWind.

---

## Design decisions (locked in)

| Detail | Decision |
|---|---|
| Prompt text | "What's on your mind?" — `text-text-tertiary` (grey #898989), `text-base-regular`, vertically centered in screen |
| Transcription text | Bottom of screen, within the glow area, `text-lime-700` (#778700) |
| Glow at rest | Very faint (opacity 0.06), no scale change |
| Glow while speaking | Brightens + scales linearly with mic amplitude (0→10) |
| Scroll bottom | Linear gradient fade mask (transparent→white) so scroll feels smooth |
| Nav bar | Caret down `∨` (chevron) on left, "Taisa" centered — caret dismisses the modal |
| Bottom controls | Stop pill (right) — submits immediately. Keyboard icon (left, inactive for now — text mode is next). |
| Auto-submit | 5s silence after first speech detected. Stop button triggers immediate submit. |
| Streaming transcription | `onSpeechPartialResults` fires per-word — each update sets `transcript` state → streams live to screen |
| Session persistence | After first Taisa response, `sessionId` stored in `chatStore`. VoiceButton reopens same session. |
| First turn | `POST /entries` → `POST /analyze` → store sessionId → show reply |
| Subsequent turns | `POST /chat/message` — appends to same session |
| Modal close | `router.back()` — VoiceButton reappears behind the modal |
| Text mode | Out of scope — separate design session |

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `mobile/src/hooks/useLiveTranscription.ts` | Create | Wraps `@react-native-voice/voice`; exposes `transcript`, `amplitude`, `isListening`, `start`, `stop`, `reset` |
| `mobile/src/stores/chatStore.ts` | Create | Holds `activeSessionId`; persists across modal open/close |
| `mobile/src/components/ui/ChatNavBar.tsx` | Create | Close button + "Taisa" title nav bar |
| `mobile/src/components/ui/RecordingGlow.tsx` | Create | Amplitude-reactive bottom glow — `expo-linear-gradient` circle |
| `mobile/src/components/ui/LiveTranscriptionText.tsx` | Create | Prompt text ↔ live transcript display |
| `mobile/src/components/ui/TaisaReplyCard.tsx` | Create (move) | Moved from `src/components/TaisaReplyCard.tsx` to DS |
| `mobile/src/components/ui/index.ts` | Modify | Export new DS components |
| `mobile/app/chat/index.tsx` | Create | Chat screen — state machine, scroll, all three sub-modes |
| `mobile/app/_layout.tsx` | Modify | Register `chat/index` route with fade animation |
| `mobile/src/components/VoiceButton.tsx` | Modify | Push to `/chat?sessionId=<id>` if session exists, else `/chat` |
| `mobile/app.json` | Modify | Add mic + speech recognition permissions |
| `mobile/app/thread/[id].tsx` | Modify | Update `TaisaReplyCard` import path |

---

## Task 1: Install `@react-native-voice/voice` and add permissions

**Files:**
- Modify: `mobile/package.json` (via npm install)
- Modify: `mobile/app.json`

- [ ] **Step 1: Install the package**

```bash
cd mobile && npm install @react-native-voice/voice
```

Expected: package appears in `mobile/package.json` dependencies.

- [ ] **Step 2: Add permissions to `app.json`**

Replace the `plugins` array in `mobile/app.json`:

```json
"plugins": [
  "expo-router",
  "expo-font",
  [
    "@react-native-voice/voice",
    {
      "microphonePermission": "Allow Taisa to access the microphone to record your voice.",
      "speechRecognitionPermission": "Allow Taisa to use speech recognition to transcribe what you say."
    }
  ]
]
```

- [ ] **Step 3: Rebuild the dev client**

This package has native modules — requires a rebuild:

```bash
cd mobile && npx expo run:ios
```

Expected: build succeeds and app launches on simulator/device with the new native module.

- [ ] **Step 4: Verify the module imports**

Open `mobile/app/recording/index.tsx` temporarily and add at the top (then remove):
```tsx
import Voice from '@react-native-voice/voice';
console.log('Voice:', Voice);
```
Start the app, check logs. Expected: `Voice: [object Object]` — not undefined or null. Remove the test import.

- [ ] **Step 5: Commit**

```bash
git add mobile/package.json mobile/package-lock.json mobile/app.json
git commit -m "feat: install @react-native-voice/voice + add mic/speech permissions"
```

---

## Task 2: `chatStore` — active session persistence

**Files:**
- Create: `mobile/src/stores/chatStore.ts`

- [ ] **Step 1: Create the store**

```typescript
// mobile/src/stores/chatStore.ts
import { create } from 'zustand';

interface ChatStore {
  activeSessionId: string | null;
  setActiveSessionId: (id: string) => void;
  clearActiveSession: () => void;
}

export const useChatStore = create<ChatStore>((set) => ({
  activeSessionId: null,
  setActiveSessionId: (id) => set({ activeSessionId: id }),
  clearActiveSession: () => set({ activeSessionId: null }),
}));
```

- [ ] **Step 2: Verify the store exports cleanly**

```bash
cd mobile && npx tsc --noEmit 2>&1 | grep chatStore
```

Expected: no errors referencing `chatStore.ts`.

- [ ] **Step 3: Commit**

```bash
git add mobile/src/stores/chatStore.ts
git commit -m "feat: add chatStore to persist active session across modal open/close"
```

---

## Task 3: `useLiveTranscription` hook

**Files:**
- Create: `mobile/src/hooks/useLiveTranscription.ts`

- [ ] **Step 1: Create the hook**

```typescript
// mobile/src/hooks/useLiveTranscription.ts
import { useEffect, useRef, useState, useCallback } from 'react';
import Voice, {
  SpeechResultsEvent,
  SpeechVolumeChangeEvent,
} from '@react-native-voice/voice';

interface UseLiveTranscription {
  transcript: string;
  isListening: boolean;
  amplitude: number; // 0–10, driven by onSpeechVolumeChanged
  start: () => Promise<void>;
  stop: () => Promise<void>;
  reset: () => void;
}

export function useLiveTranscription(): UseLiveTranscription {
  const [transcript, setTranscript] = useState('');
  const [isListening, setIsListening] = useState(false);
  const [amplitude, setAmplitude] = useState(0);
  const transcriptRef = useRef('');
  const shouldRestartRef = useRef(false);

  useEffect(() => {
    Voice.onSpeechStart = () => setIsListening(true);

    // iOS speech recognizer stops after silence — auto-restart to keep listening.
    Voice.onSpeechEnd = () => {
      setIsListening(false);
      if (shouldRestartRef.current) {
        Voice.start('en-US').catch(() => {});
      }
    };

    Voice.onSpeechPartialResults = (e: SpeechResultsEvent) => {
      const text = e.value?.[0] ?? '';
      setTranscript(text);
      transcriptRef.current = text;
    };

    Voice.onSpeechResults = (e: SpeechResultsEvent) => {
      const text = e.value?.[0] ?? '';
      setTranscript(text);
      transcriptRef.current = text;
    };

    Voice.onSpeechVolumeChanged = (e: SpeechVolumeChangeEvent) => {
      const v = typeof e.value === 'number' ? e.value : 0;
      setAmplitude(Math.max(0, Math.min(10, v)));
    };

    Voice.onSpeechError = () => {
      // Restart on error if still active (e.g., recognizer timed out)
      if (shouldRestartRef.current) {
        setTimeout(() => Voice.start('en-US').catch(() => {}), 300);
      }
    };

    return () => {
      shouldRestartRef.current = false;
      Voice.destroy().then(Voice.removeAllListeners).catch(() => {});
    };
  }, []);

  const start = useCallback(async () => {
    shouldRestartRef.current = true;
    await Voice.start('en-US');
    setIsListening(true);
  }, []);

  const stop = useCallback(async () => {
    shouldRestartRef.current = false;
    await Voice.stop();
    setIsListening(false);
    setAmplitude(0);
  }, []);

  const reset = useCallback(() => {
    setTranscript('');
    transcriptRef.current = '';
    setAmplitude(0);
    setIsListening(false);
  }, []);

  return { transcript, isListening, amplitude, start, stop, reset };
}
```

- [ ] **Step 2: Type-check**

```bash
cd mobile && npx tsc --noEmit 2>&1 | grep useLiveTranscription
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add mobile/src/hooks/useLiveTranscription.ts
git commit -m "feat: useLiveTranscription hook — wraps @react-native-voice/voice with auto-restart + amplitude"
```

---

## Task 4: `ChatNavBar` DS component

**Files:**
- Create: `mobile/src/components/ui/ChatNavBar.tsx`

- [ ] **Step 1: Create the component**

The close button uses a caret-down chevron (∨) matching the Figma design — signals "drag down to close" rather than a hard dismiss.

```tsx
// mobile/src/components/ui/ChatNavBar.tsx
import { View, Text, TouchableOpacity } from 'react-native';
import { Icon } from './Icon';

export interface ChatNavBarProps {
  onClose: () => void;
}

export function ChatNavBar({ onClose }: ChatNavBarProps) {
  return (
    <View className="flex-row items-center px-4 pt-14 pb-3">
      <TouchableOpacity onPress={onClose} className="w-10 items-start">
        <Icon name="IconChevronDown" size={20} color="#898989" />
      </TouchableOpacity>
      <Text className="flex-1 text-center text-foreground text-base-medium">
        Taisa
      </Text>
      <View className="w-10" />
    </View>
  );
}
```

- [ ] **Step 2: Type-check**

```bash
cd mobile && npx tsc --noEmit 2>&1 | grep ChatNavBar
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add mobile/src/components/ui/ChatNavBar.tsx
git commit -m "feat(ds): ChatNavBar — close button + centered Taisa title"
```

---

## Task 5: `RecordingGlow` DS component

**Files:**
- Create: `mobile/src/components/ui/RecordingGlow.tsx`

The glow is a large lime circle centred below the bottom edge of the screen.
Only its upper arc is visible. Amplitude (0–10) drives scale and opacity:
- At rest (0): opacity 0.06, scale 1.0 — barely visible
- Peak (10): opacity 0.55, scale 1.8 — prominent warm glow

- [ ] **Step 1: Create the component**

```tsx
// mobile/src/components/ui/RecordingGlow.tsx
import { useEffect, useRef } from 'react';
import { Animated, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';

export interface RecordingGlowProps {
  amplitude: number; // 0–10
}

export function RecordingGlow({ amplitude }: RecordingGlowProps) {
  const animValue = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    Animated.timing(animValue, {
      toValue: amplitude,
      duration: 120,
      useNativeDriver: true,
    }).start();
  }, [amplitude]);

  const scale = animValue.interpolate({
    inputRange: [0, 10],
    outputRange: [1, 1.8],
    extrapolate: 'clamp',
  });

  const opacity = animValue.interpolate({
    inputRange: [0, 10],
    outputRange: [0.06, 0.55],
    extrapolate: 'clamp',
  });

  return (
    // The outer View clips to the screen bottom — only the arc of the circle shows.
    <View
      style={{
        position: 'absolute',
        bottom: 0,
        left: 0,
        right: 0,
        height: 200,
        overflow: 'hidden',
        pointerEvents: 'none',
      }}
    >
      <Animated.View
        style={{
          position: 'absolute',
          bottom: -180,
          alignSelf: 'center',
          width: 400,
          height: 400,
          borderRadius: 200,
          overflow: 'hidden',
          transform: [{ scale }],
          opacity,
        }}
      >
        <LinearGradient
          colors={['#cdec1a', '#cdec1a99', 'transparent']}
          locations={[0, 0.45, 1]}
          start={{ x: 0.5, y: 1 }}
          end={{ x: 0.5, y: 0 }}
          style={{ flex: 1 }}
        />
      </Animated.View>
    </View>
  );
}
```

- [ ] **Step 2: Type-check**

```bash
cd mobile && npx tsc --noEmit 2>&1 | grep RecordingGlow
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add mobile/src/components/ui/RecordingGlow.tsx
git commit -m "feat(ds): RecordingGlow — amplitude-reactive lime glow anchored to bottom"
```

---

## Task 6: `LiveTranscriptionText` DS component

**Files:**
- Create: `mobile/src/components/ui/LiveTranscriptionText.tsx`

Shows "What's on your mind?" (grey) when no transcript exists.
Switches to the live transcript text (foreground) as words come in.

- [ ] **Step 1: Create the component**

Two states:
- No transcript → "What's on your mind?" centered, `text-text-tertiary` (grey)
- Has transcript → streaming transcription, `text-lime-700` (olive-lime, matching Figma #798057 ≈ `text-lime-700`)

Text streams live because `onSpeechPartialResults` in the hook updates `transcript` on every word — React re-renders this component automatically.

```tsx
// mobile/src/components/ui/LiveTranscriptionText.tsx
import { Text, View } from 'react-native';

export interface LiveTranscriptionTextProps {
  transcript: string;
}

export function LiveTranscriptionText({ transcript }: LiveTranscriptionTextProps) {
  const hasTranscript = transcript.length > 0;

  return (
    <View className="flex-1 items-center justify-center px-8">
      <Text
        className={`text-base-regular text-center ${
          hasTranscript ? 'text-lime-700' : 'text-text-tertiary'
        }`}
      >
        {hasTranscript ? transcript : "What's on your mind?"}
      </Text>
    </View>
  );
}
```

- [ ] **Step 2: Type-check**

```bash
cd mobile && npx tsc --noEmit 2>&1 | grep LiveTranscriptionText
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add mobile/src/components/ui/LiveTranscriptionText.tsx
git commit -m "feat(ds): LiveTranscriptionText — prompt ↔ live transcript display"
```

---

## Task 7: Move `TaisaReplyCard` into the DS

Currently at `mobile/src/components/TaisaReplyCard.tsx`. Moving to `ui/` because it will be used in both the chat screen and thread screen.

**Files:**
- Create: `mobile/src/components/ui/TaisaReplyCard.tsx`
- Modify: `mobile/src/components/ui/index.ts`
- Modify: `mobile/app/thread/[id].tsx` (import path)

- [ ] **Step 1: Read the existing component**

Read `mobile/src/components/TaisaReplyCard.tsx` to copy it exactly.

- [ ] **Step 2: Create DS version**

Write the same content to `mobile/src/components/ui/TaisaReplyCard.tsx` (no changes to the component itself — just moved).

- [ ] **Step 3: Add to `ui/index.ts`**

Append these four new exports to `mobile/src/components/ui/index.ts`:

```typescript
export { ChatNavBar } from './ChatNavBar';
export type { ChatNavBarProps } from './ChatNavBar';

export { RecordingGlow } from './RecordingGlow';
export type { RecordingGlowProps } from './RecordingGlow';

export { LiveTranscriptionText } from './LiveTranscriptionText';
export type { LiveTranscriptionTextProps } from './LiveTranscriptionText';

export { TaisaReplyCard } from './TaisaReplyCard';
```

- [ ] **Step 4: Update `thread/[id].tsx` import**

Change line 6 in `mobile/app/thread/[id].tsx`:
```tsx
// Before
import { TaisaReplyCard } from '../../src/components/TaisaReplyCard';
// After
import { TaisaReplyCard } from '../../src/components/ui/TaisaReplyCard';
```

- [ ] **Step 5: Delete the old file**

```bash
rm "mobile/src/components/TaisaReplyCard.tsx"
```

- [ ] **Step 6: Type-check**

```bash
cd mobile && npx tsc --noEmit 2>&1 | grep -i "taisa"
```

Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add mobile/src/components/ui/TaisaReplyCard.tsx mobile/src/components/ui/index.ts mobile/app/thread/[id].tsx
git rm mobile/src/components/TaisaReplyCard.tsx
git commit -m "feat(ds): move TaisaReplyCard into ui/ + export all new DS components"
```

---

## Task 8: Chat screen (`mobile/app/chat/index.tsx`)

**Files:**
- Create: `mobile/app/chat/index.tsx`

### State machine

```
idle      → auto-start listening on mount
listening → transcript updates live, glow reacts to amplitude
            5s silence timer resets on every transcript change
            when timer fires → stop listening → processing
processing → POST /entries + /analyze (first turn) or POST /chat/message (continuation)
responded → TaisaReplyCard appended to messages list
            2s delay → auto-restart listening (back to listening)
error     → show error + Retry button → back to idle
```

### First turn vs continuation

- No `sessionId` in `chatStore` → create journal entry + analyze → store returned sessionId
- `sessionId` exists in `chatStore` → send as chat message to existing session

### Key implementation note

`handleSubmit` reads `sessionIdRef` (a ref, not state) to avoid stale closure issues.
`sessionIdRef` is updated synchronously after the first turn creates a session.

- [ ] **Step 1: Create the screen**

Layout (top → bottom):
- `ChatNavBar` (caret + "Taisa")
- Conversation scroll area (flex-1, bottom fade mask)
- Input zone — vertically fixed height, contains:
  - "What's on your mind?" centered (idle, no transcript)
  - Streaming transcription text in lime-700 (while speaking)
  - Bottom control row: keyboard icon (left, inactive) + Stop pill (right)
- `RecordingGlow` — positioned absolute at screen bottom, amplitude-reactive

`onSpeechPartialResults` fires on each word — sets `transcript` state on every update, streaming the text live to `LiveTranscriptionText`.

```tsx
// mobile/app/chat/index.tsx
import { useEffect, useRef, useState } from 'react';
import {
  View,
  ScrollView,
  Text,
  TouchableOpacity,
} from 'react-native';
import { router } from 'expo-router';
import { LinearGradient } from 'expo-linear-gradient';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useLiveTranscription } from '../../src/hooks/useLiveTranscription';
import { useChatStore } from '../../src/stores/chatStore';
import {
  ChatNavBar,
  RecordingGlow,
  LiveTranscriptionText,
  TaisaReplyCard,
} from '../../src/components/ui';
import { Icon } from '../../src/components/ui';
import api from '../../src/services/api';
import type { ChatMessage } from '../../src/stores/threadStore';

type ChatPhase = 'idle' | 'listening' | 'processing' | 'responded' | 'error';

export default function ChatScreen() {
  const insets = useSafeAreaInsets();
  const { activeSessionId, setActiveSessionId } = useChatStore();

  // Ref so handleSubmit always reads the latest sessionId without a stale closure.
  const sessionIdRef = useRef<string | null>(activeSessionId);

  const [phase, setPhase] = useState<ChatPhase>('idle');
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [error, setError] = useState<string | null>(null);
  const scrollRef = useRef<ScrollView>(null);
  const silenceTimerRef = useRef<ReturnType<typeof setTimeout>>();

  const { transcript, amplitude, start, stop, reset } = useLiveTranscription();

  // Auto-scroll when messages update.
  useEffect(() => {
    if (messages.length > 0) {
      setTimeout(() => scrollRef.current?.scrollToEnd({ animated: true }), 100);
    }
  }, [messages.length]);

  // Load existing messages + start listening on mount.
  useEffect(() => {
    if (activeSessionId) {
      loadSession(activeSessionId);
    } else {
      startListening();
    }
    return () => {
      clearTimeout(silenceTimerRef.current);
    };
  }, []);

  // 5s silence detection: resets on every transcript change (streaming updates from onSpeechPartialResults).
  useEffect(() => {
    if (!transcript) return;
    clearTimeout(silenceTimerRef.current);
    silenceTimerRef.current = setTimeout(() => {
      handleSubmit(transcript);
    }, 5000);
    return () => clearTimeout(silenceTimerRef.current);
  }, [transcript]);

  async function loadSession(sessionId: string) {
    try {
      const res = await api.get(`/chat/session/${sessionId}`);
      const loaded: ChatMessage[] = res.data.data.messages ?? [];
      setMessages(loaded);
    } catch {
      // Couldn't load history — proceed fresh.
    }
    setTimeout(startListening, 2000);
  }

  async function startListening() {
    try {
      await start();
      setPhase('listening');
    } catch {
      setError('Microphone permission denied. Please allow access in Settings.');
      setPhase('error');
    }
  }

  async function handleSubmit(text: string) {
    const trimmed = text.trim();
    if (!trimmed) return;

    clearTimeout(silenceTimerRef.current);
    await stop();
    setPhase('processing');

    try {
      let reply: string;

      if (sessionIdRef.current) {
        // Continuation turn — send to existing session.
        const res = await api.post('/chat/message', {
          sessionId: sessionIdRef.current,
          message: trimmed,
        });
        reply = res.data.data.reply;
      } else {
        // First turn — create journal entry then analyze.
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
        reply = analyzeRes.data.data.reply;

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
      reset();

      // Auto-restart listening after Taisa responds.
      setTimeout(startListening, 2000);
    } catch (e: any) {
      setError(e.message ?? 'Something went wrong. Tap to retry.');
      setPhase('error');
    }
  }

  function handleStop() {
    // Immediate submit — same path as silence detection.
    clearTimeout(silenceTimerRef.current);
    if (transcript.trim()) {
      handleSubmit(transcript);
    }
  }

  function handleRetry() {
    setError(null);
    reset();
    startListening();
  }

  function handleClose() {
    clearTimeout(silenceTimerRef.current);
    stop().catch(() => {});
    router.back();
  }

  const isInputActive = phase === 'idle' || phase === 'listening';

  return (
    <View className="flex-1 bg-background">
      <ChatNavBar onClose={handleClose} />

      {/* Conversation scroll — grows to fill available space */}
      <View className="flex-1">
        <ScrollView
          ref={scrollRef}
          className="flex-1"
          contentContainerStyle={{ paddingHorizontal: 16, paddingBottom: 24 }}
          showsVerticalScrollIndicator={false}
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
              <TouchableOpacity
                onPress={handleRetry}
                className="bg-muted rounded-full px-6 py-3"
              >
                <Text className="text-foreground text-small-semibold">Try again</Text>
              </TouchableOpacity>
            </View>
          )}
        </ScrollView>

        {/* Bottom fade mask — content fades out smoothly into the input zone */}
        <LinearGradient
          colors={['transparent', '#ffffff']}
          style={{
            position: 'absolute',
            bottom: 0,
            left: 0,
            right: 0,
            height: 48,
            pointerEvents: 'none',
          }}
        />
      </View>

      {/* Input zone — fixed height, always visible during voice mode */}
      {isInputActive && (
        <View style={{ height: 200 }}>
          {/* Transcription / prompt text — streams live via onSpeechPartialResults */}
          <LiveTranscriptionText transcript={transcript} />

          {/* Bottom control row */}
          <View
            className="flex-row items-center justify-between px-5"
            style={{ paddingBottom: insets.bottom + 12 }}
          >
            {/* Keyboard toggle — inactive placeholder (text mode is next design session) */}
            <View className="w-10 h-10 rounded-full border border-border items-center justify-center opacity-40">
              <Icon name="IconKeyboard" size={20} color="#898989" />
            </View>

            {/* Stop pill — immediate submit */}
            <TouchableOpacity
              onPress={handleStop}
              disabled={!transcript.trim()}
              className="flex-row items-center gap-2 bg-background border border-border rounded-full px-4 py-2"
              style={{ opacity: transcript.trim() ? 1 : 0.4 }}
            >
              <Icon name="IconStopCircle" size={18} color="#060707" />
              <Text className="text-foreground text-small-semibold">Stop</Text>
            </TouchableOpacity>
          </View>
        </View>
      )}

      {/* Amplitude-reactive glow — positioned absolute, bottom of screen */}
      <RecordingGlow amplitude={phase === 'listening' ? amplitude : 0} />
    </View>
  );
}
```

- [ ] **Step 2: Type-check**

```bash
cd mobile && npx tsc --noEmit 2>&1 | grep "chat/index"
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add mobile/app/chat/index.tsx
git commit -m "feat: chat screen — voice mode with live transcription, 5s auto-submit, session persistence"
```

---

## Task 9: Register `/chat` route + wire VoiceButton

**Files:**
- Modify: `mobile/app/_layout.tsx`
- Modify: `mobile/src/components/VoiceButton.tsx`

- [ ] **Step 1: Register the chat route in `_layout.tsx`**

In `mobile/app/_layout.tsx`, add a `Stack.Screen` for the chat route inside the existing `<Stack>`. Add it after the recording screen:

```tsx
<Stack.Screen
  name="chat/index"
  options={{ presentation: 'modal', animation: 'fade' }}
/>
```

Full updated Stack block (for reference — only add the new screen, don't touch others):
```tsx
<Stack screenOptions={{ headerShown: false, animation: 'none', contentStyle: { backgroundColor: '#ffffff' } }}>
  <Stack.Screen name="(tabs)" />
  <Stack.Screen name="onboarding/index" />
  <Stack.Screen name="thread/[id]" />
  <Stack.Screen
    name="recording/index"
    options={{ presentation: 'transparentModal', animation: 'slide_from_bottom' }}
  />
  <Stack.Screen
    name="chat/index"
    options={{ presentation: 'modal', animation: 'fade' }}
  />
</Stack>
```

- [ ] **Step 2: Update `VoiceButton` to push to `/chat`**

Replace the `handlePress` line in `mobile/src/components/VoiceButton.tsx`:

```tsx
// Before
import { router } from 'expo-router';
// ...
const handlePress = onPress ?? (() => router.push('/recording'));
```

```tsx
// After — add chatStore import at top
import { useChatStore } from '../stores/chatStore';

// Inside VoiceButton component:
const { activeSessionId } = useChatStore();
const handlePress = onPress ?? (() => {
  if (activeSessionId) {
    router.push({ pathname: '/chat', params: { sessionId: activeSessionId } });
  } else {
    router.push('/chat');
  }
});
```

Full updated `VoiceButton.tsx`:

```tsx
import { Pressable } from 'react-native';
import { router } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withTiming,
  withSpring,
} from 'react-native-reanimated';
import { Icon } from './ui/Icon';
import { colors } from '../constants/theme';
import { useChatStore } from '../stores/chatStore';

interface VoiceButtonProps {
  onPress?: () => void;
}

export function VoiceButton({ onPress }: VoiceButtonProps) {
  const insets = useSafeAreaInsets();
  const { activeSessionId } = useChatStore();

  const handlePress = onPress ?? (() => {
    if (activeSessionId) {
      router.push({ pathname: '/chat', params: { sessionId: activeSessionId } });
    } else {
      router.push('/chat');
    }
  });

  const scale = useSharedValue(1);

  const animStyle = useAnimatedStyle(() => ({
    transform: [{ scale: scale.value }],
  }));

  return (
    <Animated.View
      style={[
        {
          position: 'absolute',
          bottom: insets.bottom + 16,
          left: 0,
          right: 0,
          alignItems: 'center',
          zIndex: 50,
        },
        animStyle,
      ]}
    >
      <Pressable
        onPress={handlePress}
        onPressIn={() => { scale.value = withTiming(0.95, { duration: 80 }); }}
        onPressOut={() => { scale.value = withSpring(1, { damping: 20, stiffness: 300 }); }}
        style={{
          backgroundColor: '#cdec1a',
          paddingVertical: 16,
          paddingHorizontal: 44,
          borderRadius: 48,
          shadowColor: colors.accent,
          shadowOffset: { width: 0, height: 0 },
          shadowOpacity: 0.6,
          shadowRadius: 24,
          elevation: 10,
        }}
      >
        <Icon name="IconVoiceMid" size={24} color="#060707" />
      </Pressable>
    </Animated.View>
  );
}
```

- [ ] **Step 3: Type-check both files**

```bash
cd mobile && npx tsc --noEmit 2>&1 | grep -E "VoiceButton|_layout"
```

Expected: no errors.

- [ ] **Step 4: Start the app and verify the happy path**

```bash
npx expo start
```

Check:
1. Tap VoiceButton → chat screen opens with fade animation, "Taisa" centered in nav bar, caret down on left
2. "What's on your mind?" visible in grey, vertically centered in screen
3. Glow barely visible at the bottom (very faint)
4. Speak → glow brightens with voice, text streams live in lime-700 in the bottom input zone
5. Tap Stop → immediate submit, or pause 5s → auto-submit
6. Processing state shows "Taisa is thinking…", then TaisaReplyCard appears in scroll
7. Auto-restarts listening 2s after response
8. Tap caret down → back to main tabs, VoiceButton visible
9. Tap VoiceButton again → chat opens, previous conversation in scroll, auto-listens after 2s delay
10. Speak again → new message appended to same session

- [ ] **Step 5: Commit**

```bash
git add mobile/app/_layout.tsx mobile/src/components/VoiceButton.tsx
git commit -m "feat: register /chat route + wire VoiceButton to continue active session"
```

---

## Self-review

### Spec coverage check

| AC from scope doc / design | Covered in plan? |
|---|---|
| Chat screen continues existing session | ✅ Task 2 (`chatStore`) + Task 8 `loadSession()` |
| Auto-ready on open — starts listening on mount | ✅ Task 8 — `startListening()` on mount |
| Live streaming transcription | ✅ Task 3 (`onSpeechPartialResults`) + Task 6 (`LiveTranscriptionText`) |
| Silence detection → auto-submit (5s) | ✅ Task 8 — `useEffect` timer resets on each `transcript` change |
| Stop button → immediate submit | ✅ Task 8 — `handleStop()` |
| Taisa's response in same view | ✅ Task 8 — appended to `messages` list |
| Error state with retry | ✅ Task 8 — `error` phase + retry button |
| Session persists across modal opens | ✅ Task 2 (`chatStore`) + Task 9 (VoiceButton reads stored ID) |
| VoiceButton reopens same convo | ✅ Task 9 — passes `sessionId` when active |
| Nav bar — caret down + "Taisa" | ✅ Task 4 — `ChatNavBar` with `IconChevronDown` |
| Glow very faint at rest, brightens with speech | ✅ Task 5 — opacity 0.06→0.55, scale 1→1.8 |
| Scroll bottom fade | ✅ Task 8 — `LinearGradient` overlay |
| Prompt text grey, transcription text lime | ✅ Task 6 — `text-text-tertiary` / `text-lime-700` |
| Keyboard icon (inactive placeholder) | ✅ Task 8 — rendered with `opacity-40`, no action |

### Items out of scope (separate build)
- Text/keyboard mode — not in this plan by user decision
- Context mode (`contextType` + `contextId`) — future entry point wiring
- `recording/index.tsx` removal — kept as-is until chat screen passes QA

### Placeholder scan

No TBDs, no "implement later", no vague steps. All code is complete.

### Type consistency

- `ChatMessage` type imported from `threadStore` throughout — consistent.
- `useLiveTranscription` returns `{ transcript, isListening, amplitude, start, stop, reset }` — all consumed in Task 8.
- `RecordingGlow` takes `amplitude: number` — matches what `useLiveTranscription` returns.
- `LiveTranscriptionText` takes `transcript: string` — matches.
- `TaisaReplyCard` takes `content: string` — matches existing component interface.

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
import Animated, { useAnimatedStyle, useSharedValue } from 'react-native-reanimated';
import { useLiveTranscription } from '../../src/hooks/useLiveTranscription';
import { useMorphTransition } from '../../src/hooks/useMorphTransition';
import { useChatStore } from '../../src/stores/chatStore';
import { useUIStore } from '../../src/stores/uiStore';
import {
  ChatNavBar,
  MorphSurface,
  RecordingGlow,
  LiveTranscriptionText,
  TaisaReplyCard,
  Icon,
} from '../../src/components/ui';
import api from '../../src/services/api';
import type { ChatMessage } from '../../src/stores/threadStore';

// rgba(255,255,255,0) → #ffffff avoids the grey band that `transparent` causes on iOS
// (transparent = rgba(0,0,0,0) which interpolates through grey to white).
const BACKGROUND_HEX = '#ffffff';
const BACKGROUND_TRANSPARENT = 'rgba(255,255,255,0)';

type ChatPhase = 'idle' | 'listening' | 'processing' | 'responded' | 'error';

export default function ChatScreen() {
  const insets = useSafeAreaInsets();
  const { activeSessionId, setActiveSessionId } = useChatStore();
  const { setChatMorphing } = useUIStore();
  const { progress, contentOpacity, open, close } = useMorphTransition();

  const contentStyle = useAnimatedStyle(() => ({
    opacity: contentOpacity.value,
  }));

  // Ref so handleSubmit always reads the latest sessionId without a stale closure.
  const sessionIdRef = useRef<string | null>(activeSessionId);

  const [phase, setPhase] = useState<ChatPhase>('idle');
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [error, setError] = useState<string | null>(null);
  const scrollRef = useRef<ScrollView>(null);
  const silenceTimerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const restartTimerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const closingRef = useRef(false);

  const { transcript, amplitude, recognizerError, start, stop, reset } = useLiveTranscription();
  // Bridge amplitude (React state number 0–10) to a SharedValue (0–1) for RecordingGlow
  const amplitudeSV = useSharedValue(0);
  useEffect(() => { amplitudeSV.value = amplitude / 10; }, [amplitude]);

  // Surface recognizer errors (e.g. permission denied after the screen is already open)
  useEffect(() => {
    if (recognizerError) {
      setError(`Speech recognizer error: ${recognizerError}. Check microphone & speech permissions in Settings.`);
      setPhase('error');
    }
  }, [recognizerError]);

  // Auto-scroll when messages update.
  useEffect(() => {
    if (messages.length > 0) {
      setTimeout(() => scrollRef.current?.scrollToEnd({ animated: true }), 100);
    }
  }, [messages.length]);

  // Load existing messages + start listening on mount.
  useEffect(() => {
    open();
    if (activeSessionId) {
      loadSession(activeSessionId);
    } else {
      startListening();
    }
    return () => {
      clearTimeout(silenceTimerRef.current);
      clearTimeout(restartTimerRef.current);
      stop().catch(() => {});
      setChatMorphing(false);
    };
  }, []);

  // 5s silence detection: resets on every transcript change (streams from partial results).
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
    restartTimerRef.current = setTimeout(startListening, 2000);
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

        // /analyze returns only sessionId — fetch the session to get the assistant reply.
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
      reset();

      // Auto-restart listening after Taisa responds.
      restartTimerRef.current = setTimeout(startListening, 2000);
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
    if (closingRef.current) return;
    closingRef.current = true;
    clearTimeout(silenceTimerRef.current);
    clearTimeout(restartTimerRef.current);
    stop().catch(() => {});
    close(() => {
      setChatMorphing(false);
      router.back();
    });
  }

  const isInputActive = phase === 'idle' || phase === 'listening';

  return (
    <View style={{ flex: 1, backgroundColor: 'transparent' }}>
      <MorphSurface progress={progress} />

      <Animated.View style={[{ flex: 1 }, contentStyle]}>
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
            colors={[BACKGROUND_TRANSPARENT, BACKGROUND_HEX]}
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
            {/* Transcription / prompt text — streams live via partial results */}
            <LiveTranscriptionText transcript={transcript} />

            {/* Bottom control row */}
            <View
              className="flex-row items-center justify-between px-5"
              style={{ paddingBottom: insets.bottom + 12 }}
            >
              {/* Keyboard toggle — inactive placeholder */}
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

        {/* Glow anchored to the screen bottom */}
        <RecordingGlow amplitude={amplitudeSV} visible={phase === 'listening'} />
      </Animated.View>
    </View>
  );
}

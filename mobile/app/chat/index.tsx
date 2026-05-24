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
import { useLiveTranscription } from '../../src/hooks/useLiveTranscription';
import { useMorphTransition } from '../../src/hooks/useMorphTransition';
import { useChatStore } from '../../src/stores/chatStore';
import { useUIStore } from '../../src/stores/uiStore';
import {
  ChatNavBar,
  RecordingGlow,
  LiveTranscriptionText,
  TaisaReplyCard,
  Icon,
} from '../../src/components/ui';
import api from '../../src/services/api';
import type { ChatMessage } from '../../src/stores/threadStore';

const BACKGROUND_HEX = '#ffffff';
const BACKGROUND_TRANSPARENT = 'rgba(255,255,255,0)';

const DISMISS_VELOCITY = 800;
const SPRING_BACK = { damping: 26, stiffness: 200 };

type ChatPhase = 'idle' | 'listening' | 'processing' | 'responded' | 'error';

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
  const silenceTimerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const restartTimerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const closingRef = useRef(false);

  const { transcript, amplitude, recognizerError, start, stop, reset } = useLiveTranscription();
  const amplitudeSV = useSharedValue(0);
  useEffect(() => { amplitudeSV.value = amplitude / 10; }, [amplitude]);

  useEffect(() => {
    if (recognizerError) {
      setError(`Speech recognizer error: ${recognizerError}. Check microphone & speech permissions in Settings.`);
      setPhase('error');
    }
  }, [recognizerError]);

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
      clearTimeout(silenceTimerRef.current);
      clearTimeout(restartTimerRef.current);
      stop().catch(() => {});
      setChatMorphing(false);
    };
  }, []);

  useEffect(() => {
    if (!transcript) return;
    clearTimeout(silenceTimerRef.current);
    silenceTimerRef.current = setTimeout(() => handleSubmit(transcript), 5000);
    return () => clearTimeout(silenceTimerRef.current);
  }, [transcript]);

  // ─── Drag-to-dismiss ────────────────────────────────────────────────────────

  const scrollAtTop = useSharedValue(true);
  const isHandlingDrag = useSharedValue(false);

  function commitClose(delay: number) {
    if (closingRef.current) return;
    closingRef.current = true;
    clearTimeout(silenceTimerRef.current);
    clearTimeout(restartTimerRef.current);
    stop().catch(() => {});
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
    setPhase('listening');
    try {
      await start();
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
      reset();
      restartTimerRef.current = setTimeout(startListening, 2000);
    } catch (e: any) {
      setError(e.message ?? 'Something went wrong. Tap to retry.');
      setPhase('error');
    }
  }

  function handleStop() {
    clearTimeout(silenceTimerRef.current);
    if (transcript.trim()) handleSubmit(transcript);
  }

  function handleRetry() {
    setError(null);
    reset();
    startListening();
  }

  function handleClose() {
    if (closingRef.current) return;
    close();
    commitClose(340);
  }

  const isInputActive = phase === 'idle' || phase === 'listening';

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

        <RecordingGlow amplitude={amplitudeSV} visible={phase === 'listening'} />

        {isInputActive && (
          <View style={{ height: 200 }}>
            <LiveTranscriptionText transcript={transcript} />
            <View
              className="flex-row items-center justify-between px-5"
              style={{ paddingBottom: insets.bottom + 12 }}
            >
              <View className="w-10 h-10 rounded-full border border-border items-center justify-center opacity-40">
                <Icon name="IconKeyboard" size={20} color="#898989" />
              </View>
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
      </Animated.View>
    </GestureDetector>
  );
}

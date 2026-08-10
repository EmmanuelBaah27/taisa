import { useCallback, useEffect, useRef, useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  useWindowDimensions,
} from 'react-native';
import { ScrollView } from 'react-native-gesture-handler';
import { LinearGradient } from 'expo-linear-gradient';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Animated, { useAnimatedStyle, useSharedValue, withSpring, withTiming, runOnJS } from 'react-native-reanimated';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import { useVoiceRecorder } from '../../src/hooks/useVoiceRecorder';
import type { RecordingResult } from '../../src/services/audio';
import { useMorphTransition } from '../../src/hooks/useMorphTransition';
import { useChatStore } from '../../src/stores/chatStore';
import { useThreadStore } from '../../src/stores/threadStore';
import { useUIStore } from '../../src/stores/uiStore';
import {
  ChatNavBar,
  RecordingGlow,
  TaisaReplyCard,
  Icon,
} from '../../src/components/ui';

const BACKGROUND_HEX = '#ffffff';
const BACKGROUND_TRANSPARENT = 'rgba(255,255,255,0)';

const DISMISS_VELOCITY = 800;
const SPRING_BACK = { damping: 26, stiffness: 200 };

export default function ChatScreen() {
  const insets = useSafeAreaInsets();
  const { height: screenH } = useWindowDimensions();
  const {
    activeSessionId,
    activeRequestId,
    transcript,
    pendingProposals,
    phase,
    error,
    setActiveSessionId,
    setPhase,
    savePrivateDraft,
    submitText,
    submitVoice,
    updateTranscript,
    confirmTranscript,
    retrySubmission,
    confirmProposal,
  } = useChatStore();
  const { currentMessages: messages, fetchThread } = useThreadStore();
  const { setChatMorphing } = useUIStore();
  const { translateY, open, close } = useMorphTransition();

  const slideStyle = useAnimatedStyle(() => ({
    flex: 1,
    transform: [{ translateY: translateY.value }],
  }));

  const sessionIdRef = useRef<string | null>(activeSessionId);
  const [draft, setDraft] = useState('');
  const [transcriptDraft, setTranscriptDraft] = useState('');
  const [pendingRecording, setPendingRecording] = useState<RecordingResult | null>(null);
  const scrollRef = useRef<ScrollView>(null);
  const restartTimerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const closingRef = useRef(false);

  const recorder = useVoiceRecorder();

  // Stop any in-flight recording without throwing when none is active.
  const stopRecorderSafe = useCallback(() => recorder.stop().catch(() => {}), []);

  useEffect(() => {
    if (messages.length > 0) {
      setTimeout(() => scrollRef.current?.scrollToEnd({ animated: true }), 100);
    }
  }, [messages.length]);

  useEffect(() => {
    setTranscriptDraft(transcript);
  }, [transcript]);

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
    await fetchThread(sessionId);
    restartTimerRef.current = setTimeout(startListening, 2000);
  }

  async function startListening() {
    if (closingRef.current) return;
    setPhase('listening');
    try {
      await recorder.start();
    } catch {
      setPhase('error');
    }
  }

  // Stopping is local-only. Transcription begins only after the separate Submit action.
  async function handleStop() {
    if (!recorder.isRecording) {
      // OS may have ended the recording (call / audio interruption); recover rather than get stuck.
      startListening();
      return;
    }
    let result: RecordingResult;
    try {
      result = await recorder.stop();
    } catch (e: any) {
      // A stop failure (e.g. no active recording due to a race with close) is not a transcription error.
      startListening();
      return;
    }
    setPendingRecording(result);
    setPhase('recording-ready');
  }

  async function refreshConversation() {
    if (sessionIdRef.current) await fetchThread(sessionIdRef.current);
  }

  async function handleSubmitText() {
    const content = draft.trim();
    if (!content) return;
    const conversationId = sessionIdRef.current ?? `conversation-${Date.now()}`;
    sessionIdRef.current = conversationId;
    setActiveSessionId(conversationId);
    try {
      await submitText(conversationId, content);
      setDraft('');
      await refreshConversation();
    } catch {}
  }

  async function handlePrivateSave() {
    const content = draft.trim();
    if (!content) return;
    const conversationId = sessionIdRef.current ?? `conversation-${Date.now()}`;
    sessionIdRef.current = conversationId;
    setActiveSessionId(conversationId);
    try {
      await savePrivateDraft(conversationId, content);
      setDraft('');
      await refreshConversation();
    } catch {}
  }

  async function handleSubmitRecording() {
    if (pendingRecording === null) return;
    const conversationId = sessionIdRef.current ?? `conversation-${Date.now()}`;
    sessionIdRef.current = conversationId;
    setActiveSessionId(conversationId);
    try {
      await submitVoice(conversationId, pendingRecording.uri, pendingRecording.durationSeconds);
      await refreshConversation();
    } catch {}
  }

  async function handleConfirmTranscript() {
    try {
      await updateTranscript(transcriptDraft);
      await confirmTranscript();
      setPendingRecording(null);
      await refreshConversation();
    } catch {}
  }

  async function handleRetry() {
    if (activeRequestId === null) {
      startListening();
      return;
    }
    try {
      await retrySubmission();
      await refreshConversation();
    } catch {}
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
            {messages.filter((message) => message.content.length > 0).map(msg =>
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
                <Text className="text-danger text-small-regular mb-3 text-center">
                  {error ?? 'Taisa could not complete this action. Your content remains on this device.'}
                </Text>
                <TouchableOpacity onPress={handleRetry} className="bg-muted rounded-full px-6 py-3">
                  <Text className="text-foreground text-small-semibold">Try again</Text>
                </TouchableOpacity>
              </View>
            )}

            {pendingProposals.map((proposal) => (
              <View key={proposal.id} className="bg-subtle rounded-3 px-4 py-3 mb-3">
                <Text className="text-foreground text-small-regular mb-3">
                  Taisa suggests remembering: {proposal.summary}
                </Text>
                <TouchableOpacity
                  onPress={() => confirmProposal(proposal.id)}
                  className="self-start bg-muted rounded-full px-4 py-2"
                >
                  <Text className="text-foreground text-small-semibold">Confirm memory</Text>
                </TouchableOpacity>
              </View>
            ))}
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
                <TouchableOpacity onPress={() => { stopRecorderSafe(); setPhase('idle'); }}>
                  <Icon name="IconKeyboard" size={20} color="#898989" />
                </TouchableOpacity>
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

        {phase === 'recording-ready' && (
          <View className="px-5" style={{ paddingBottom: insets.bottom + 12 }}>
            <Text className="text-text-tertiary text-small-regular mb-3 text-center">
              This recording is still only on your phone.
            </Text>
            <View className="flex-row gap-3">
              <TouchableOpacity onPress={startListening} className="flex-1 border border-border rounded-full px-4 py-3">
                <Text className="text-foreground text-small-semibold text-center">Record again</Text>
              </TouchableOpacity>
              <TouchableOpacity onPress={handleSubmitRecording} className="flex-1 bg-muted rounded-full px-4 py-3">
                <Text className="text-foreground text-small-semibold text-center">Submit to Taisa</Text>
              </TouchableOpacity>
            </View>
          </View>
        )}

        {phase === 'transcript-review' && (
          <View className="px-5" style={{ paddingBottom: insets.bottom + 12 }}>
            <Text className="text-text-tertiary text-small-regular mb-2">Review the transcript before coaching</Text>
            <TextInput
              value={transcriptDraft}
              onChangeText={setTranscriptDraft}
              multiline
              className="bg-subtle rounded-3 px-4 py-3 text-foreground text-base-regular mb-3"
            />
            <Text className="text-text-tertiary text-small-regular mb-3 text-center">
              Confirming sends this transcript and selected local context for external AI processing.
            </Text>
            <TouchableOpacity onPress={handleConfirmTranscript} className="bg-muted rounded-full px-4 py-3">
              <Text className="text-foreground text-small-semibold text-center">Confirm and submit</Text>
            </TouchableOpacity>
          </View>
        )}

        {(phase === 'idle' || phase === 'responded') && (
          <View className="px-5" style={{ paddingBottom: insets.bottom + 12 }}>
            <TextInput
              value={draft}
              onChangeText={setDraft}
              placeholder="Write a work thought…"
              multiline
              className="bg-subtle rounded-3 px-4 py-3 text-foreground text-base-regular mb-3"
            />
            <Text className="text-text-tertiary text-small-regular mb-3 text-center">
              Private save stays on this phone. Submit sends this thought and selected local context for external AI processing.
            </Text>
            <View className="flex-row gap-3">
              <TouchableOpacity onPress={handlePrivateSave} className="flex-1 border border-border rounded-full px-4 py-3">
                <Text className="text-foreground text-small-semibold text-center">Private save</Text>
              </TouchableOpacity>
              <TouchableOpacity onPress={handleSubmitText} className="flex-1 bg-muted rounded-full px-4 py-3">
                <Text className="text-foreground text-small-semibold text-center">Submit to Taisa</Text>
              </TouchableOpacity>
            </View>
          </View>
        )}
      </Animated.View>
    </GestureDetector>
  );
}

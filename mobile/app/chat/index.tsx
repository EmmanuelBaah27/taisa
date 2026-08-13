import { useEffect, useReducer, useRef, useState } from 'react';
import {
  Alert,
  useWindowDimensions,
} from 'react-native';
import type { ScrollView } from 'react-native-gesture-handler';
import { router, useLocalSearchParams } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useAnimatedStyle, useSharedValue, withSpring, withTiming, runOnJS } from 'react-native-reanimated';
import { Gesture } from 'react-native-gesture-handler';
import { useVoiceRecorder } from '../../src/hooks/useVoiceRecorder';
import type { RecordingResult } from '../../src/services/audio';
import {
  createRecordingCleanupBarrier,
  createRecordingStartGuard,
  createRecordingStopSession,
  stopOwnedRecordingAndDiscard,
  type RecordingStopSession,
} from '../../src/services/recordingStopSession';
import {
  createRecordingSubmissionLease,
  type RecordingSubmissionLease,
} from '../../src/services/recordingSubmissionLease';
import { useMorphTransition } from '../../src/hooks/useMorphTransition';
import { canAbandonVoiceSubmission, useChatStore } from '../../src/stores/chatStore';
import { useThreadStore } from '../../src/stores/threadStore';
import { useUIStore } from '../../src/stores/uiStore';
import {
  closeChatPresentation,
  isConversationCacheCurrent,
  resolveInitialChatConversationId,
  returnFromRoutedChat,
  type ChatPresentation,
} from '../../src/navigation/chatConversationRoute';
import {
  RecordingGlow,
  VoiceComposer,
  ChatComposerDock,
  ChatConversationSurface,
  ChatScreenShell,
} from '../../src/components/ui';
import {
  createVoiceComposerState,
  reduceVoiceComposer,
} from '../../src/services/voiceComposerState';
import { withTaisaDatabase } from '../../src/db/openDatabase';
import { withRepositoryTransaction } from '../../src/db/types';
import {
  getResponseFeedback,
  markFeedbackLocalOnly,
  markFeedbackShared,
  saveResponseReaction,
  type ResponseReaction,
} from '../../src/repositories/responseFeedbackRepository';
import { buildFeedbackPreview } from '../../src/services/feedbackBundle';
import api from '../../src/services/api';
import { createFeedbackClient } from '../../src/services/feedbackClient';

const DISMISS_VELOCITY = 800;
const SPRING_BACK = { damping: 26, stiffness: 200 };

interface ChatScreenProps {
  presentation?: ChatPresentation;
}

function promptEditable(title: string, value: string): Promise<string | null> {
  return new Promise((resolve) => {
    Alert.prompt(
      title,
      'Remove or replace anything you do not want to share.',
      [
        { text: 'Cancel', style: 'cancel', onPress: () => resolve(null) },
        { text: 'Continue', onPress: (edited?: string) => resolve(edited?.trim() || '') },
      ],
      'plain-text',
      value,
    );
  });
}

export default function ChatScreen({ presentation = 'route' }: ChatScreenProps) {
  const insets = useSafeAreaInsets();
  const { height: screenH } = useWindowDimensions();
  const { conversationId: routeConversationId } = useLocalSearchParams<{
    conversationId?: string | string[];
  }>();
  const {
    activeSessionId,
    activeRequestId,
    activeRequestKind,
    activeRequestStatus,
    activeMessageId,
    transcript: storedTranscript,
    pendingProposals: storedPendingProposals,
    phase: storedPhase,
    isBusy,
    error: storedError,
    setActiveSessionId,
    setPreferredInputMode,
    setPhase,
    drainAudioCleanupQueue,
    hydrateConversation,
    savePrivateDraft,
    submitText,
    submitVoice,
    updateTranscript,
    confirmTranscript,
    reviseTranscript,
    retrySubmission,
    confirmProposal,
    resolveClarification,
    discardRecording,
    abandonVoiceSubmission,
  } = useChatStore();
  const {
    currentSession,
    currentMessages: storedMessages,
    fetchThread,
    fetchThreads,
  } = useThreadStore();
  const { setChatMorphing, consumeVoiceAutoStart } = useUIStore();
  const { translateY, open, close } = useMorphTransition();

  const slideStyle = useAnimatedStyle(() => ({
    flex: 1,
    transform: [{ translateY: translateY.value }],
  }));

  const initialConversationId = resolveInitialChatConversationId(
    routeConversationId,
    activeSessionId,
    presentation === 'overlay',
  );
  const initialConversationIdRef = useRef<string | null>(initialConversationId);
  const sessionIdRef = useRef<string | null>(initialConversationIdRef.current);
  const [initialHydrationComplete, setInitialHydrationComplete] = useState(
    initialConversationIdRef.current === null,
  );
  const [draft, setDraft] = useState('');
  const [composer, dispatchComposer] = useReducer(
    reduceVoiceComposer,
    undefined,
    createVoiceComposerState,
  );
  const [transcriptDraft, setTranscriptDraft] = useState('');
  const [pendingRecording, setPendingRecording] = useState<RecordingResult | null>(null);
  const [recordingStartFailed, setRecordingStartFailed] = useState(false);
  const [editingTranscript, setEditingTranscript] = useState<string | null>(null);
  const [reactions, setReactions] = useState<Record<string, ResponseReaction>>({});
  const pendingRecordingRef = useRef<RecordingResult | null>(null);
  const scrollRef = useRef<ScrollView>(null);
  const restartTimerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const closingRef = useRef(false);
  const mountedRef = useRef(true);
  const recordingStartGuardRef = useRef(createRecordingStartGuard());
  const recordingStopSessionRef = useRef<RecordingStopSession | null>(null);
  const recordingCleanupBarrierRef = useRef(createRecordingCleanupBarrier());
  const recordingSubmissionLeaseRef = useRef<RecordingSubmissionLease | null>(null);

  const isHydratingInitialConversation = !initialHydrationComplete;
  const transcript = isHydratingInitialConversation ? '' : storedTranscript;
  const pendingProposals = isHydratingInitialConversation ? [] : storedPendingProposals;
  const phase = isHydratingInitialConversation ? 'processing' : storedPhase;
  const error = isHydratingInitialConversation ? null : storedError;
  const messages = !isHydratingInitialConversation && isConversationCacheCurrent(
    sessionIdRef.current,
    currentSession?.id ?? null,
  )
    ? storedMessages
    : [];

  const recorder = useVoiceRecorder();

  function discardPendingRecording() {
    if (recordingSubmissionLeaseRef.current !== null) {
      recordingSubmissionLeaseRef.current.requestCleanup();
      return;
    }
    const pending = pendingRecordingRef.current;
    if (pending === null) return;
    pendingRecordingRef.current = null;
    void discardRecording(pending.uri).catch(() => {});
  }

  function stopActiveRecordingAndDiscard(): Promise<void> {
    return recordingCleanupBarrierRef.current.run(
      () => stopOwnedRecordingAndDiscard(
        recordingStopSessionRef,
        recordingStartGuardRef.current,
      ),
    );
  }

  useEffect(() => {
    if (messages.length > 0) {
      setTimeout(() => scrollRef.current?.scrollToEnd({ animated: true }), 100);
    }
  }, [messages.length]);

  useEffect(() => {
    const responseIds = messages
      .filter((message) => message.role === 'assistant')
      .map((message) => message.id);
    if (responseIds.length === 0) {
      setReactions({});
      return;
    }
    let active = true;
    void withTaisaDatabase(async (database) => {
      const stored = await Promise.all(responseIds.map((id) => getResponseFeedback(database, id)));
      if (!active) return;
      setReactions(Object.fromEntries(stored
        .filter((item) => item !== null)
        .map((item) => [item.responseMessageId, item.reaction])));
    }).catch(() => {});
    return () => { active = false; };
  }, [messages]);

  useEffect(() => {
    setTranscriptDraft(transcript);
  }, [transcript]);

  useEffect(() => {
    pendingRecordingRef.current = pendingRecording;
  }, [pendingRecording]);

  useEffect(() => {
    mountedRef.current = true;
    open();
    void drainAudioCleanupQueue().catch(() => {});
    if (consumeVoiceAutoStart()) {
      handleSwitchToVoice();
      void startListening();
    }
    if (initialConversationIdRef.current) {
      void loadSession(initialConversationIdRef.current).catch(() => {});
    }
    return () => {
      mountedRef.current = false;
      clearTimeout(restartTimerRef.current);
      void stopActiveRecordingAndDiscard().catch(() => {});
      discardPendingRecording();
      if (presentation === 'overlay') setChatMorphing(false);
    };
  }, []);

  // ─── Drag-to-dismiss ────────────────────────────────────────────────────────

  const scrollAtTop = useSharedValue(true);
  const isHandlingDrag = useSharedValue(false);

  function commitClose(delay: number) {
    if (closingRef.current) return;
    closingRef.current = true;
    clearTimeout(restartTimerRef.current);
    void stopActiveRecordingAndDiscard().catch(() => {});
    discardPendingRecording();
    restartTimerRef.current = setTimeout(() => {
      closeChatPresentation(presentation, {
        closeRoute: () => returnFromRoutedChat({
          canGoBack: () => router.canGoBack(),
          back: () => router.back(),
          replace: (path) => router.replace(path),
        }),
        closeOverlay: () => setChatMorphing(false),
      });
    }, delay);
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
      await hydrateConversation(sessionId);
      await fetchThread(sessionId);
      const hydrated = useChatStore.getState();
      dispatchComposer({
        type: 'restore-mode',
        mode: hydrated.preferredInputMode,
      });
      if (
        hydrated.activeRequestKind === 'voice' &&
        (hydrated.activeRequestStatus === 'transcription-failed' ||
          hydrated.activeRequestStatus === 'coaching-failed')
      ) dispatchComposer({ type: 'submission-failed' });
    } finally {
      if (mountedRef.current) setInitialHydrationComplete(true);
    }
  }

  async function startListening() {
    await recordingCleanupBarrierRef.current.wait();
    if (closingRef.current || !mountedRef.current || recordingStopSessionRef.current !== null) {
      return;
    }
    const startAttempt = recordingStartGuardRef.current.begin();
    if (startAttempt === null) return;
    setRecordingStartFailed(false);
    setPhase('listening');
    try {
      await recorder.start();
      dispatchComposer({ type: 'start-voice' });
      const session = createRecordingStopSession({
        stop: recorder.stop,
        discard: discardRecording,
      });
      recordingStopSessionRef.current = session;
      if (
        !recordingStartGuardRef.current.complete(startAttempt) ||
        !mountedRef.current ||
        closingRef.current
      ) {
        recordingStopSessionRef.current = null;
        await session.stopAndDiscard();
      }
    } catch {
      const isCurrentAttempt = recordingStartGuardRef.current.complete(startAttempt);
      if (isCurrentAttempt && mountedRef.current && !closingRef.current) {
        setRecordingStartFailed(true);
        setPhase('error');
      }
    }
  }

  async function handlePauseVoice() {
    try {
      await recorder.pause();
      dispatchComposer({ type: 'pause-voice' });
    } catch {
      if (mountedRef.current) setPhase('error');
    }
  }

  async function handleResumeVoice() {
    try {
      await recorder.resume();
      dispatchComposer({ type: 'resume-voice' });
    } catch {
      if (mountedRef.current) setPhase('error');
    }
  }

  async function handleSwitchToText() {
    const activity = recorder.getActivity();
    if (composer.voice === 'recording' || composer.voice === 'paused') {
      if (activity !== 'speech') {
        await stopActiveRecordingAndDiscard();
      } else if (composer.voice === 'recording') {
        await recorder.pause();
      }
    }
    dispatchComposer({ type: 'switch-to-text', activity });
    if (sessionIdRef.current !== null) {
      void setPreferredInputMode(sessionIdRef.current, 'text').catch(() => {});
    }
    setPhase('idle');
  }

  function handleSwitchToVoice() {
    dispatchComposer({ type: 'switch-to-voice' });
    const conversationId = sessionIdRef.current ?? `conversation-${Date.now()}`;
    sessionIdRef.current = conversationId;
    setActiveSessionId(conversationId);
    void setPreferredInputMode(conversationId, 'voice').catch(() => {});
    setPhase('idle');
  }

  function handleStartVoiceFromComposer() {
    handleSwitchToVoice();
    void startListening();
  }

  function handleUseKeyboard() {
    setRecordingStartFailed(false);
    dispatchComposer({ type: 'restore-mode', mode: 'text' });
    const conversationId = sessionIdRef.current ?? `conversation-${Date.now()}`;
    sessionIdRef.current = conversationId;
    setActiveSessionId(conversationId);
    void setPreferredInputMode(conversationId, 'text').catch(() => {});
    setPhase('idle');
  }

  async function confirmVoiceDraftDeletion() {
    const requestId = canAbandonVoiceSubmission({
      activeRequestId,
      activeRequestKind,
      activeRequestStatus,
    }) ? activeRequestId : null;
    if (requestId !== null) await abandonVoiceSubmission(requestId);

    const pending = pendingRecordingRef.current;
    await stopActiveRecordingAndDiscard();
    if (pending !== null) await discardRecording(pending.uri);
    pendingRecordingRef.current = null;
    if (mountedRef.current) setPendingRecording(null);
    dispatchComposer({ type: 'confirm-delete-voice' });
  }

  function handleDeleteVoiceDraft() {
    Alert.alert(
      'Delete voice draft?',
      'This recording will be permanently removed.',
      [
        { text: 'Keep it', style: 'cancel', onPress: () => dispatchComposer({ type: 'cancel-delete-voice' }) },
        {
          text: 'Delete recording',
          style: 'destructive',
          onPress: () => {
            void confirmVoiceDraftDeletion().catch(() => {
              dispatchComposer({ type: 'cancel-delete-voice' });
              if (mountedRef.current) setPhase('error');
            });
          },
        },
      ],
    );
    dispatchComposer({ type: 'request-delete-voice' });
  }

  async function handleComposerSend() {
    if (isBusy) return;
    dispatchComposer({ type: 'send' });
    if (composer.voice === 'none') {
      await handleSubmitText();
      dispatchComposer({ type: 'reset' });
      return;
    }
    const session = recordingStopSessionRef.current;
    const result = pendingRecordingRef.current ?? await session?.stopForReview() ?? null;
    recordingStopSessionRef.current = null;
    if (result === null) return;
    pendingRecordingRef.current = null;
    setPendingRecording(null);
    dispatchComposer({ type: 'pause-voice' });
    const conversationId = sessionIdRef.current ?? `conversation-${Date.now()}`;
    sessionIdRef.current = conversationId;
    setActiveSessionId(conversationId);
    try {
      await submitVoice(conversationId, result.uri, result.durationSeconds, draft.trim() || undefined);
      setDraft('');
      dispatchComposer({ type: 'reset' });
      await refreshConversation();
    } catch {
      pendingRecordingRef.current = result;
      setPendingRecording(result);
      dispatchComposer({ type: 'submission-failed' });
    }
  }

  async function handleSaveTranscriptRevision() {
    const corrected = editingTranscript?.trim() ?? '';
    if (!corrected) return;
    const revisionConversationId = sessionIdRef.current;
    try {
      await reviseTranscript(corrected);
      setEditingTranscript(null);
      dispatchComposer({ type: 'reset' });
    } catch {
      // The durable revision transaction already retired the superseded reply and proposals.
    } finally {
      if (
        revisionConversationId !== null &&
        mountedRef.current &&
        sessionIdRef.current === revisionConversationId &&
        useChatStore.getState().activeSessionId === revisionConversationId
      ) {
        await refreshConversation();
      }
    }
  }

  // Stopping is local-only. Transcription begins only after the separate Submit action.
  async function handleStop() {
    const session = recordingStopSessionRef.current;
    if (session === null) {
      await stopActiveRecordingAndDiscard();
      if (mountedRef.current) setPhase('idle');
      return;
    }
    const result = await session.stopForReview();
    if (recordingStopSessionRef.current !== session) return;
    recordingStopSessionRef.current = null;
    if (result === null) {
      await startListening();
      return;
    }
    if (!mountedRef.current || closingRef.current) {
      await discardRecording(result.uri);
      return;
    }
    pendingRecordingRef.current = result;
    setPendingRecording(result);
    setPhase('recording-ready');
  }

  async function refreshConversation() {
    if (sessionIdRef.current) await fetchThread(sessionIdRef.current);
    await fetchThreads();
  }

  async function handleReaction(responseId: string, reaction: ResponseReaction) {
    const note = await new Promise<string | null>((resolve) => {
      if (reaction === 'helpful') return resolve(null);
      Alert.prompt(
        'What could be better?',
        'Optional. This stays on your phone unless you separately share the example.',
        [
          { text: 'Skip', onPress: () => resolve(null) },
          { text: 'Save', onPress: (value?: string) => resolve(value?.trim() || null) },
        ],
        'plain-text',
      );
    });
    await withTaisaDatabase((database) => withRepositoryTransaction(database, (transaction) =>
      saveResponseReaction(transaction, {
        responseMessageId: responseId,
        reaction,
        note,
        updatedAt: new Date().toISOString(),
      })));
    setReactions((current) => ({ ...current, [responseId]: reaction }));
  }

  async function handleShareExample(responseId: string) {
    try {
      const [preview, feedback] = await withTaisaDatabase(async (database) => Promise.all([
        buildFeedbackPreview(database, responseId),
        getResponseFeedback(database, responseId),
      ]));
      if (feedback === null) throw new Error('Feedback is unavailable');
      if (feedback.shareStatus === 'shared' && feedback.shareReceiptId !== null) {
        Alert.alert(
          'Shared example',
          'The encrypted example is in your private feedback store. Your local reaction will remain if you delete it there.',
          [
            { text: 'Keep it', style: 'cancel' },
            {
              text: 'Delete shared copy',
              style: 'destructive',
              onPress: () => {
                void createFeedbackClient(api).remove(feedback.shareReceiptId!).then(() =>
                  withTaisaDatabase((database) => withRepositoryTransaction(database, (transaction) =>
                    markFeedbackLocalOnly(transaction, responseId, new Date().toISOString()))))
                  .then(() => Alert.alert('Shared copy deleted', 'Your reaction remains on this phone.'))
                  .catch(() => Alert.alert('Could not delete', 'Try again when Taisa is connected.'));
              },
            },
          ],
        );
        return;
      }
      Alert.alert(
        'Review before sharing',
        `Nothing has been sent. This example includes:\n\nYou: ${preview.userTurn}\n\nTaisa: ${preview.assistantReply}\n\nContext used (${preview.usedContext.length}):\n${preview.usedContext.join('\n') || 'No earlier context'}\n\nOnly tap Share if you consent to sending this example to your private Taisa feedback store.`,
        [
          { text: 'Keep local', style: 'cancel' },
          {
            text: 'Redact & review',
            onPress: () => {
              void (async () => {
                const userTurn = await promptEditable('Review your message', preview.userTurn);
                if (userTurn === null) return;
                const assistantReply = await promptEditable('Review Taisa’s response', preview.assistantReply);
                if (assistantReply === null) return;
                const context = await promptEditable('Review the context used', preview.usedContext.join('\n'));
                if (context === null) return;
                Alert.alert(
                  'Share this example?',
                  'This sends only the reviewed text and context to your encrypted private feedback store. You can delete it later.',
                  [
                    { text: 'Keep local', style: 'cancel' },
                    {
                      text: 'Share',
                      onPress: () => {
                        const consentedAt = new Date().toISOString();
                        void createFeedbackClient(api).share({
                          idempotencyId: `${responseId}:share-v1`,
                          consentedAt,
                          reaction: feedback.reaction,
                          note: feedback.note,
                          draft: {
                            ...preview,
                            userTurn,
                            assistantReply,
                            usedContext: context ? [context] : [],
                          },
                        }).then(({ receiptId }) => withTaisaDatabase((database) =>
                          withRepositoryTransaction(database, (transaction) => markFeedbackShared(
                            transaction,
                            responseId,
                            consentedAt,
                            receiptId,
                            new Date().toISOString(),
                          )))).then(() => {
                          Alert.alert('Example shared', 'You can delete the shared example later from Taisa.');
                        }).catch(() => {
                          Alert.alert('Could not share', 'The feedback remains only on your phone.');
                        });
                      },
                    },
                  ],
                );
              })();
            },
          },
        ],
      );
    } catch {
      Alert.alert('Preview unavailable', 'This feedback remains only on your phone.');
    }
  }

  async function handleSubmitText() {
    const content = draft.trim();
    if (!content) return;
    const conversationId = sessionIdRef.current ?? `conversation-${Date.now()}`;
    sessionIdRef.current = conversationId;
    setActiveSessionId(conversationId);
    try {
      await submitText(conversationId, content);
      if (mountedRef.current) setDraft('');
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
      if (mountedRef.current) setDraft('');
      await refreshConversation();
    } catch {}
  }

  async function handleSubmitRecording() {
    if (pendingRecording === null || isBusy) return;
    const submittedRecording = pendingRecording;
    pendingRecordingRef.current = null;
    const submissionLease = createRecordingSubmissionLease(submittedRecording);
    recordingSubmissionLeaseRef.current = submissionLease;
    const conversationId = sessionIdRef.current ?? `conversation-${Date.now()}`;
    sessionIdRef.current = conversationId;
    setActiveSessionId(conversationId);
    let succeeded = false;
    let durableRequestExists = false;
    try {
      await submitVoice(
        conversationId,
        submittedRecording.uri,
        submittedRecording.durationSeconds,
      );
      succeeded = true;
      durableRequestExists = true;
      await refreshConversation();
    } catch (submissionError) {
      durableRequestExists = typeof submissionError === 'object' &&
        submissionError !== null &&
        'requestId' in submissionError;
    } finally {
      const settlement = submissionLease.settle({
        succeeded,
        durableRequestExists,
        captureStillOpen: mountedRef.current && !closingRef.current,
      });
      if (recordingSubmissionLeaseRef.current === submissionLease) {
        recordingSubmissionLeaseRef.current = null;
      }
      if (settlement.outcome === 'discard') {
        await discardRecording(submittedRecording.uri).catch(() => {});
      } else if (settlement.outcome === 'retain') {
        pendingRecordingRef.current = submittedRecording;
        if (mountedRef.current) setPhase('recording-ready');
      } else if (mountedRef.current) {
        setPendingRecording(null);
      }
    }
  }

  async function handleConfirmTranscript() {
    try {
      await updateTranscript(transcriptDraft);
      await confirmTranscript();
      pendingRecordingRef.current = null;
      if (mountedRef.current) setPendingRecording(null);
      dispatchComposer({ type: 'reset' });
      await refreshConversation();
    } catch {}
  }

  async function handleRecordAgain() {
    try {
      if (phase === 'transcript-review' && activeRequestId !== null) {
        await abandonVoiceSubmission(activeRequestId);
      }
      if (pendingRecording !== null) {
        await discardRecording(pendingRecording.uri);
      }
    } catch {
      if (mountedRef.current) setPhase('error');
      return;
    }
    if (pendingRecording !== null) {
      pendingRecordingRef.current = null;
      if (mountedRef.current) setPendingRecording(null);
    }
    await startListening();
  }

  async function handleRetry() {
    if (activeRequestId === null) {
      if (pendingRecordingRef.current !== null) await handleComposerSend();
      return;
    }
    try {
      await retrySubmission();
      if (mountedRef.current) setDraft('');
      if (activeRequestKind === 'voice') dispatchComposer({ type: 'reset' });
      await refreshConversation();
    } catch {}
  }

  async function handleDiscardFailedRecording() {
    if (activeRequestKind !== 'voice' || isBusy) return;
    try {
      await confirmVoiceDraftDeletion();
    } catch {}
  }

  function handleClose() {
    if (closingRef.current) return;
    close();
    commitClose(340);
  }

  return (
    <ChatScreenShell
      topInset={insets.top}
      gesture={dragGesture}
      animatedStyle={slideStyle}
      onClose={handleClose}
      footer={(
        <ChatComposerDock phase={phase} bottomInset={insets.bottom}>
          <VoiceComposer
            mode={composer.mode}
            voiceState={composer.voice}
            durationSeconds={pendingRecording?.durationSeconds ?? recorder.duration}
            amplitude={recorder.amplitude}
            text={draft}
            hasVoiceDraft={composer.voice !== 'none'}
            submissionFailed={composer.submissionFailed}
            textFocusRequest={composer.textFocusRequest}
            disabled={isBusy}
            onChangeText={(value) => {
              setDraft(value);
              dispatchComposer({ type: 'set-text', text: value });
            }}
            onSwitchToText={() => { void handleSwitchToText(); }}
            onSwitchToVoice={handleSwitchToVoice}
            onStartVoice={handleStartVoiceFromComposer}
            onPause={() => { void handlePauseVoice(); }}
            onResume={() => { void handleResumeVoice(); }}
            onDeleteText={() => {
              setDraft('');
              dispatchComposer({ type: 'delete-text' });
            }}
            onDeleteVoice={handleDeleteVoiceDraft}
            onSend={() => { void handleComposerSend(); }}
          />
        </ChatComposerDock>
      )}
    >
      <ChatConversationSurface
        scrollRef={scrollRef}
        messages={messages}
        activeMessageId={activeMessageId}
        activeRequestKind={activeRequestKind}
        transcript={transcript}
        phase={phase}
        isBusy={isBusy}
        error={error}
        microphoneUnavailable={recordingStartFailed}
        pendingProposals={pendingProposals}
        editingTranscript={editingTranscript}
        reactions={reactions}
        onScrollAtTopChange={(atTop) => { scrollAtTop.value = atTop; }}
        onEditTranscript={setEditingTranscript}
        onChangeTranscript={setEditingTranscript}
        onSubmitTranscript={() => { void handleSaveTranscriptRevision(); }}
        onUseKeyboard={handleUseKeyboard}
        onDiscardRecording={handleDiscardFailedRecording}
        onRetry={recordingStartFailed ? startListening : handleRetry}
        onConfirmProposal={(proposalId) => { void confirmProposal(proposalId); }}
        onResolveProposal={(proposalId, choice) => { void resolveClarification(proposalId, choice); }}
        onReact={(responseId, reaction) => { void handleReaction(responseId, reaction); }}
        onShareExample={(responseId) => { void handleShareExample(responseId); }}
      />
      <RecordingGlow
        amplitude={recorder.amplitude}
        visible={composer.mode === 'voice' && composer.voice === 'recording'}
      />
    </ChatScreenShell>
  );
}

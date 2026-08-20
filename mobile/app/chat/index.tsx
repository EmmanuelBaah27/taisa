import { useEffect, useReducer, useRef, useState } from 'react';
import {
  Alert,
  Keyboard,
  Platform,
  View,
  useWindowDimensions,
} from 'react-native';
import { router, useLocalSearchParams } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import {
  runOnJS,
  useAnimatedStyle,
  useSharedValue,
  withSpring,
  withTiming,
} from 'react-native-reanimated';
import {
  Gesture, GestureDetector, type GestureType, type ScrollView,
} from 'react-native-gesture-handler';
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
  resolveInitialChatConversationId,
  selectConversationMessages,
  returnFromRoutedChat,
  voiceCancelAccessibilityLabel,
  voiceCancelDestination,
  type ChatPresentation,
} from '../../src/navigation/chatConversationRoute';
import {
  VoiceComposer,
  ChatComposerDock,
  ChatConversationSurface,
  ChatScreenShell,
  ActiveRecordingActionBar,
  ActiveRecordingContent,
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
import {
  CHAT_SHEET_DISMISS_DURATION,
  CHAT_SHEET_RETURN_SPRING,
  getResistedChatSheetTranslation,
  parseChatCardSource,
  shouldDismissChatSheet,
} from '../../src/navigation/chatCardExpansion';
import { isRecorderAcquiring } from '../../src/services/recorderAcquisition';
import {
  confirmDestructiveInput,
  type DestructiveInputIntent,
} from '../../src/services/destructiveInputConfirmation';
import { playInteractionHaptic } from '../../src/services/interactionHaptics';

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
  const { height: viewportHeight } = useWindowDimensions();
  const routeParams = useLocalSearchParams<{
    conversationId?: string | string[];
    cardX?: string | string[];
    cardY?: string | string[];
    cardWidth?: string | string[];
    cardHeight?: string | string[];
    listScrollY?: string | string[];
    sourceViewportWidth?: string | string[];
    sourceViewportHeight?: string | string[];
  }>();
  const routeConversationId = routeParams.conversationId;
  const {
    activeSessionId,
    activeRequestId,
    activeRequestKind,
    activeRequestStatus,
    activeMessageId,
    transcript: storedTranscript,
    provisionalTranscript,
    transcriptionOutcome,
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
  const sourceSnapshot = parseChatCardSource(routeParams);
  const conversationAtTop = useSharedValue(true);
  const sheetPanRef = useRef<GestureType | undefined>(undefined);
  const {
    translateX,
    translateY,
    scaleX,
    scaleY,
    borderRadius,
    shellOpacity,
    contentOpacity,
    contentTranslateY,
    open,
    revealContent,
  } = useMorphTransition(sourceSnapshot);

  const slideStyle = useAnimatedStyle(() => ({
    flex: 1,
    borderRadius: borderRadius.value,
    opacity: shellOpacity.value,
    transform: [
      { translateX: translateX.value },
      { translateY: translateY.value },
      { scaleX: scaleX.value },
      { scaleY: scaleY.value },
    ],
  }));
  const contentStyle = useAnimatedStyle(() => ({
    opacity: contentOpacity.value,
    transform: [{ translateY: contentTranslateY.value }],
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
  const [keyboardVisible, setKeyboardVisible] = useState(false);
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
  const closingRef = useRef(false);
  const mountedRef = useRef(true);
  const recordingStartGuardRef = useRef(createRecordingStartGuard());
  const recordingStopSessionRef = useRef<RecordingStopSession | null>(null);
  const recordingCleanupBarrierRef = useRef(createRecordingCleanupBarrier());
  const recordingSubmissionLeaseRef = useRef<RecordingSubmissionLease | null>(null);
  const initialBottomSettledRef = useRef(false);
  const previousMessageCountRef = useRef(0);

  const isHydratingInitialConversation = !initialHydrationComplete;
  const transcript = isHydratingInitialConversation ? '' : storedTranscript;
  const pendingProposals = isHydratingInitialConversation ? [] : storedPendingProposals;
  const phase = isHydratingInitialConversation ? 'processing' : storedPhase;
  const error = isHydratingInitialConversation ? null : storedError;
  const messages = selectConversationMessages(
    isHydratingInitialConversation ? null : sessionIdRef.current,
    currentSession?.id ?? null,
    storedMessages,
  );

  const recorder = useVoiceRecorder();
  const recorderAcquiring = isRecorderAcquiring(
    composer.voice,
    pendingRecording !== null,
    recorder.isRecording,
  );
  const hasAbandonableVoiceSubmission = canAbandonVoiceSubmission({
    activeRequestId,
    activeRequestKind,
    activeRequestStatus,
  });
  const hasDestructiveDraft = draft.trim().length > 0
    || composer.voice === 'recording'
    || composer.voice === 'paused'
    || pendingRecording !== null
    || hasAbandonableVoiceSubmission;

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
    const showEvent = Platform.OS === 'ios' ? 'keyboardWillShow' : 'keyboardDidShow';
    const hideEvent = Platform.OS === 'ios' ? 'keyboardWillHide' : 'keyboardDidHide';
    const show = Keyboard.addListener(showEvent, (event) => {
      if (Platform.OS === 'ios') Keyboard.scheduleLayoutAnimation(event);
      setKeyboardVisible(true);
    });
    const hide = Keyboard.addListener(hideEvent, (event) => {
      if (Platform.OS === 'ios') Keyboard.scheduleLayoutAnimation(event);
      setKeyboardVisible(false);
    });
    return () => { show.remove(); hide.remove(); };
  }, []);

  useEffect(() => {
    if (initialBottomSettledRef.current && messages.length > previousMessageCountRef.current) {
      setTimeout(() => scrollRef.current?.scrollToEnd({ animated: true }), 100);
    }
    previousMessageCountRef.current = messages.length;
  }, [messages.length]);

  function handleConversationContentSizeChange() {
    if (!initialHydrationComplete || initialBottomSettledRef.current) return;
    scrollRef.current?.scrollToEnd({ animated: false });
    initialBottomSettledRef.current = true;
    previousMessageCountRef.current = messages.length;
    requestAnimationFrame(revealContent);
  }

  useEffect(() => {
    if (transcriptionOutcome !== 'uncertain' || !transcript.trim()) return;
    setDraft(transcript);
    dispatchComposer({ type: 'load-uncertain-transcript', text: transcript });
  }, [transcript, transcriptionOutcome]);

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
      void stopActiveRecordingAndDiscard().catch(() => {});
      discardPendingRecording();
      setChatMorphing(false);
    };
  }, []);

  function commitClose() {
    closeChatPresentation(presentation, {
      closeRoute: () => returnFromRoutedChat({
        canGoBack: () => router.canGoBack(),
        back: () => router.back(),
        replace: (path) => router.replace(path),
      }),
      closeOverlay: () => setChatMorphing(false),
    });
  }

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
    if (closingRef.current || !mountedRef.current || recordingStopSessionRef.current !== null) {
      return;
    }
    setRecordingStartFailed(false);
    setPhase('listening');
    dispatchComposer({ type: 'start-voice' });

    await recordingCleanupBarrierRef.current.wait();
    if (closingRef.current || !mountedRef.current || recordingStopSessionRef.current !== null) {
      if (mountedRef.current && !closingRef.current) {
        dispatchComposer({ type: 'recording-start-failed' });
        setPhase('idle');
      }
      return;
    }
    const startAttempt = recordingStartGuardRef.current.begin();
    if (startAttempt === null) {
      dispatchComposer({ type: 'recording-start-failed' });
      setPhase('idle');
      return;
    }
    try {
      await recorder.start();
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
        await handleCancelVoice();
      }
    }
  }

  async function handlePauseVoice() {
    if (recorderAcquiring) return;
    try {
      await recorder.pause();
      playInteractionHaptic('selection');
      dispatchComposer({ type: 'pause-voice' });
    } catch {
      if (mountedRef.current) {
        Alert.alert('Couldn’t pause recording', 'Keep speaking or try Pause again.');
      }
    }
  }

  async function handleResumeVoice() {
    try {
      await recorder.resume();
      playInteractionHaptic('selection');
      dispatchComposer({ type: 'resume-voice' });
    } catch {
      if (mountedRef.current) setPhase('error');
    }
  }

  async function handleSwitchToText() {
    await stopActiveRecordingAndDiscard();
    discardPendingRecording();
    pendingRecordingRef.current = null;
    if (mountedRef.current) setPendingRecording(null);
    dispatchComposer({ type: 'restore-mode', mode: 'text' });
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

  async function requestDestructiveInput(
    intent: DestructiveInputIntent,
    onConfirm: () => void | Promise<void>,
  ): Promise<boolean> {
    const confirmed = await confirmDestructiveInput(intent);
    if (!confirmed) return false;
    await onConfirm();
    return true;
  }

  function handleDeleteVoiceDraft() {
    dispatchComposer({ type: 'request-delete-voice' });
    void requestDestructiveInput('delete-voice-draft', confirmVoiceDraftDeletion)
      .then((confirmed) => {
        if (!confirmed) dispatchComposer({ type: 'cancel-delete-voice' });
      })
      .catch(() => {
        dispatchComposer({ type: 'cancel-delete-voice' });
        if (mountedRef.current) setPhase('error');
      });
  }

  async function handleComposerSend() {
    if (recorderAcquiring) return;
    if (isBusy) return;
    if (composer.voice === 'none' && !draft.trim()) return;
    playInteractionHaptic('send');
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
      const transcription = useChatStore.getState();
      if (transcription.transcriptionOutcome !== 'uncertain') {
        setDraft('');
        dispatchComposer({ type: 'reset' });
      }
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
    if (sourceSnapshot === null) await fetchThreads();
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
      await requestDestructiveInput('discard-voice-submission', confirmVoiceDraftDeletion);
    } catch {}
  }

  function performClose(withDismissHaptic = true) {
    if (closingRef.current) return;
    if (withDismissHaptic) playInteractionHaptic('dismiss');
    closingRef.current = true;
    void stopActiveRecordingAndDiscard().catch(() => {});
    discardPendingRecording();
    translateY.value = withTiming(
      viewportHeight,
      { duration: CHAT_SHEET_DISMISS_DURATION },
      (finished) => {
        if (finished) runOnJS(commitClose)();
      },
    );
  }

  function handleClose() {
    if (!hasDestructiveDraft) {
      performClose();
      return;
    }
    const intent = hasAbandonableVoiceSubmission
      ? 'discard-voice-submission'
      : 'cancel-recording';
    void requestDestructiveInput(intent, () => performClose(false));
  }

  function completeGestureClose() {
    if (closingRef.current) return;
    closingRef.current = true;
    void stopActiveRecordingAndDiscard().catch(() => {});
    discardPendingRecording();
    commitClose();
  }

  function animateGestureClose() {
    translateY.value = withTiming(
      viewportHeight,
      { duration: CHAT_SHEET_DISMISS_DURATION },
      (finished) => {
        if (finished) runOnJS(completeGestureClose)();
      },
    );
  }

  function handleGestureDestructiveClose() {
    if (hasAbandonableVoiceSubmission) {
      void requestDestructiveInput('discard-voice-submission', animateGestureClose);
      return;
    }
    void requestDestructiveInput('cancel-recording', animateGestureClose);
  }

  const sheetPanGesture = Gesture.Pan()
    .withRef(sheetPanRef)
    .activeOffsetY(8)
    .failOffsetX([-24, 24])
    .onUpdate((event) => {
      if (!conversationAtTop.value || event.translationY <= 0) return;
      translateY.value = getResistedChatSheetTranslation(event.translationY);
    })
    .onEnd((event) => {
      if (shouldDismissChatSheet({
        atTop: conversationAtTop.value,
        translationY: event.translationY,
        velocityY: event.velocityY,
      })) {
        if (hasDestructiveDraft) {
          translateY.value = withSpring(0, CHAT_SHEET_RETURN_SPRING, (finished) => {
            if (finished) runOnJS(handleGestureDestructiveClose)();
          });
          return;
        }
        runOnJS(playInteractionHaptic)('dismiss');
        translateY.value = withTiming(
          viewportHeight,
          { duration: CHAT_SHEET_DISMISS_DURATION },
          (finished) => {
            if (finished) runOnJS(completeGestureClose)();
          },
        );
        return;
      }
      translateY.value = withSpring(0, CHAT_SHEET_RETURN_SPRING);
    });

  async function handleCancelVoice() {
    if (voiceCancelDestination(initialConversationIdRef.current) === 'close') {
      performClose(false);
      return;
    }

    await stopActiveRecordingAndDiscard();
    discardPendingRecording();
    if (!mountedRef.current) return;
    setPendingRecording(null);
    setRecordingStartFailed(false);
    setPhase('idle');
    dispatchComposer({ type: 'restore-mode', mode: 'voice' });
  }

  const showActiveRecordingSurface = messages.length === 0
    && initialConversationIdRef.current === null
    && composer.mode === 'voice'
    && (composer.voice === 'recording' || composer.voice === 'paused')
    && !composer.submissionFailed
    && !composer.submitting
    && !isBusy;

  useEffect(() => {
    if (!showActiveRecordingSurface) return;
    requestAnimationFrame(revealContent);
    // revealContent intentionally stays out of this dependency list because useMorphTransition
    // returns a new function each render; the recording-state transition is the reveal trigger.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [showActiveRecordingSurface]);

  const chatContent = showActiveRecordingSurface ? (
    <ActiveRecordingContent greeting="How’s it going?" />
  ) : (
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
      onScrollAtTopChange={(atTop) => { conversationAtTop.value = atTop; }}
      dismissGestureRef={sheetPanRef}
      onContentSizeChange={handleConversationContentSizeChange}
      reactions={reactions}
      onEditTranscript={setEditingTranscript}
      onChangeTranscript={setEditingTranscript}
      onSubmitTranscript={() => { void handleSaveTranscriptRevision(); }}
      onUseKeyboard={handleUseKeyboard}
      onDiscardRecording={handleDiscardFailedRecording}
      onRetry={recordingStartFailed || activeRequestStatus === 'no-speech' ? startListening : handleRetry}
      onConfirmProposal={(proposalId) => { void confirmProposal(proposalId); }}
      onResolveProposal={(proposalId, choice) => { void resolveClarification(proposalId, choice); }}
      onReact={(responseId, reaction) => { void handleReaction(responseId, reaction); }}
      onShareExample={(responseId) => { void handleShareExample(responseId); }}
    />
  );

  const chatFooter = (
    <ChatComposerDock phase={phase} bottomInset={keyboardVisible ? 0 : insets.bottom}>
      {showActiveRecordingSurface ? (
        <ActiveRecordingActionBar
          durationSeconds={recorder.duration}
          amplitudeLevel={recorder.amplitudeLevel}
          paused={composer.voice === 'paused'}
          disabled={composer.submitting || isBusy}
          recordingActionDisabled={recorderAcquiring}
          cancelLabel={voiceCancelAccessibilityLabel(initialConversationIdRef.current)}
          onCancel={() => {
            void requestDestructiveInput('cancel-recording', handleCancelVoice);
          }}
          onKeyboard={() => {
            void requestDestructiveInput('switch-to-keyboard', handleSwitchToText);
          }}
          onPauseResume={() => {
            if (composer.voice === 'paused') void handleResumeVoice();
            else void handlePauseVoice();
          }}
          onSend={() => { void handleComposerSend(); }}
        />
      ) : (
        <VoiceComposer
          mode={transcriptionOutcome === 'streaming' ? 'text' : composer.mode}
          voiceState={composer.voice}
          durationSeconds={pendingRecording?.durationSeconds ?? recorder.duration}
          amplitude={recorder.amplitude}
          text={transcriptionOutcome === 'streaming' ? provisionalTranscript : draft}
          hasVoiceDraft={composer.voice !== 'none'}
          submissionFailed={composer.submissionFailed}
          recordingStartFailed={recordingStartFailed}
          textFocusRequest={composer.textFocusRequest}
          disabled={isBusy}
          recordingActionDisabled={recorderAcquiring}
          transcribing={transcriptionOutcome === 'streaming'}
          cancelVoiceLabel={voiceCancelAccessibilityLabel(initialConversationIdRef.current)}
          onChangeText={(value) => {
            setDraft(value);
            dispatchComposer({ type: 'set-text', text: value });
          }}
          onSwitchToText={() => {
            void requestDestructiveInput('switch-to-keyboard', handleSwitchToText);
          }}
          onSwitchToVoice={handleSwitchToVoice}
          onStartVoice={handleStartVoiceFromComposer}
          onPause={() => { void handlePauseVoice(); }}
          onResume={() => { void handleResumeVoice(); }}
          onCancelVoice={() => {
            void requestDestructiveInput('cancel-recording', handleCancelVoice);
          }}
          onDeleteText={() => {
            setDraft('');
            dispatchComposer({ type: 'delete-text' });
          }}
          onDeleteVoice={handleDeleteVoiceDraft}
          onSend={() => { void handleComposerSend(); }}
        />
      )}
    </ChatComposerDock>
  );

  return (
    <GestureDetector gesture={sheetPanGesture}>
      <View collapsable={false} style={{ flex: 1 }}>
        <ChatScreenShell
          topInset={insets.top}
          title="Taisa"
          animatedStyle={slideStyle}
          contentAnimatedStyle={contentStyle}
          onClose={handleClose}
          footer={chatFooter}
        >
          {chatContent}
        </ChatScreenShell>
      </View>
    </GestureDetector>
  );
}

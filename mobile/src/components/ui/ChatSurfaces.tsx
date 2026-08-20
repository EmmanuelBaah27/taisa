import { Component, type ReactNode, type RefObject } from 'react';
import {
  KeyboardAvoidingView,
  Platform,
  Text,
  TouchableOpacity,
  View,
  type StyleProp,
  type ViewStyle,
} from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { ScrollView } from 'react-native-gesture-handler';
import type { GestureType } from 'react-native-gesture-handler';
import Animated from 'react-native-reanimated';

import { colors } from '../../constants/theme';
import type { ClarificationChoice, PendingProposal } from '../../services/privateCapture';
import type { ChatPhase } from '../../stores/chatStore';
import type { ChatMessage } from '../../stores/threadStore';
import { ChatNavBar } from './ChatNavBar';
import { TaisaReplyCard } from './TaisaReplyCard';
import type { ResponseReaction } from '../../repositories/responseFeedbackRepository';
import { TranscriptCorrectionCard } from './TranscriptCorrectionCard';

export interface ChatScreenShellProps {
  topInset: number;
  title: string;
  animatedStyle: StyleProp<ViewStyle>;
  contentAnimatedStyle: StyleProp<ViewStyle>;
  onClose: () => void;
  children: ReactNode;
  footer: ReactNode;
}

export function ChatScreenShell({
  topInset,
  title,
  animatedStyle,
  contentAnimatedStyle,
  onClose,
  children,
  footer,
}: ChatScreenShellProps) {
  return (
    <KeyboardAvoidingView
      className="flex-1"
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
        <Animated.View className="flex-1 overflow-hidden bg-background" style={animatedStyle}>
          <Animated.View
            testID="chat-page"
            className="flex-1 px-5"
            style={contentAnimatedStyle}
          >
            <ChatNavBar title={title} topInset={topInset} onClose={onClose} />
            {children}
            {footer}
          </Animated.View>
        </Animated.View>
    </KeyboardAvoidingView>
  );
}

export interface ChatMessageBubbleProps {
  content: string;
  editable?: boolean;
  showCorrectionHint?: boolean;
  onEdit?: () => void;
}

export function ChatMessageBubble({
  content,
  editable = false,
  showCorrectionHint = false,
  onEdit,
}: ChatMessageBubbleProps) {
  return (
    <TouchableOpacity
      accessibilityLabel={editable ? 'Correct voice transcript' : undefined}
      disabled={!editable}
      onPress={onEdit}
      className="mb-8 max-w-[336px] self-end bg-muted px-4 py-4"
      style={{ borderRadius: 28 }}
    >
      <Text className="text-foreground text-base-regular">{content}</Text>
      {showCorrectionHint ? (
        <Text className="mt-1 text-text-tertiary text-caption-regular">Tap to correct transcript</Text>
      ) : null}
    </TouchableOpacity>
  );
}

export interface PendingTranscriptBubbleProps {
  transcript: string;
}

export function PendingTranscriptBubble({ transcript }: PendingTranscriptBubbleProps) {
  return (
    <View className="mb-3 max-w-xs self-end rounded-3 bg-lime-100 px-4 py-3">
      <Text className="text-foreground text-base-regular">{transcript}</Text>
      <Text className="mt-1 text-text-tertiary text-caption-regular">
        Transcribed · you can correct this afterward
      </Text>
    </View>
  );
}

export function ChatProcessingBubble() {
  return (
    <View className="mb-3 items-start">
      <View className="rounded-3 bg-subtle px-4 py-3">
        <Text className="text-text-tertiary text-small-regular">Taisa is thinking…</Text>
      </View>
    </View>
  );
}

interface ChatActionProps {
  label: string;
  disabled?: boolean;
  emphasized?: boolean;
  onPress: () => void;
}

function ChatAction({ label, disabled, emphasized, onPress }: ChatActionProps) {
  return (
    <TouchableOpacity
      accessibilityLabel={label}
      disabled={disabled}
      onPress={onPress}
      className={emphasized
        ? 'rounded-full bg-muted px-6 py-3'
        : 'rounded-full border border-border px-6 py-3'}
    >
      <Text className="text-foreground text-small-semibold">{label}</Text>
    </TouchableOpacity>
  );
}

export interface ChatErrorPanelProps {
  message: string;
  microphoneUnavailable: boolean;
  voiceRequest: boolean;
  disabled?: boolean;
  onUseKeyboard: () => void;
  onDiscardRecording: () => void;
  onRetry: () => void;
}

export function ChatErrorPanel(props: ChatErrorPanelProps) {
  return (
    <View className="items-center py-4">
      <Text className="mb-3 text-center text-danger text-small-regular">{props.message}</Text>
      <View className="flex-row gap-3">
        {props.microphoneUnavailable ? (
          <ChatAction label="Use keyboard" onPress={props.onUseKeyboard} />
        ) : null}
        {props.voiceRequest ? (
          <ChatAction
            label="Discard recording"
            disabled={props.disabled}
            onPress={props.onDiscardRecording}
          />
        ) : null}
        <ChatAction
          label={props.microphoneUnavailable ? 'Try microphone again' : 'Try again'}
          disabled={props.disabled}
          emphasized
          onPress={props.onRetry}
        />
      </View>
    </View>
  );
}

export interface PendingProposalCardProps {
  proposal: PendingProposal;
  disabled?: boolean;
  onConfirm: (proposalId: string) => void;
  onResolve: (proposalId: string, choice: ClarificationChoice) => void;
}

export function PendingProposalCard({
  proposal,
  disabled,
  onConfirm,
  onResolve,
}: PendingProposalCardProps) {
  return (
    <View className="mb-3 rounded-3 bg-subtle px-4 py-3">
      <Text className="mb-3 text-foreground text-small-regular">
        {proposal.kind === 'clarification'
          ? proposal.question
          : `Taisa suggests remembering: ${proposal.summary}`}
      </Text>
      {proposal.kind === 'clarification' ? (
        <View className="gap-2">
          <ChatAction label="Replace old direction" disabled={disabled} emphasized onPress={() => onResolve(proposal.id, 'replace')} />
          <ChatAction label="Pause old direction" disabled={disabled} onPress={() => onResolve(proposal.id, 'pause')} />
          <ChatAction label="Keep both" disabled={disabled} onPress={() => onResolve(proposal.id, 'coexist')} />
        </View>
      ) : (
        <ChatAction label="Confirm memory" disabled={disabled} emphasized onPress={() => onConfirm(proposal.id)} />
      )}
    </View>
  );
}

export interface ChatConversationSurfaceProps {
  scrollRef: RefObject<ScrollView | null>;
  messages: readonly ChatMessage[];
  activeMessageId: string | null;
  activeRequestKind: 'text' | 'voice' | null;
  transcript: string;
  phase: ChatPhase;
  isBusy: boolean;
  error: string | null;
  microphoneUnavailable: boolean;
  pendingProposals: readonly PendingProposal[];
  editingTranscript: string | null;
  reactions?: Readonly<Record<string, ResponseReaction>>;
  onScrollAtTopChange?: (atTop: boolean) => void;
  dismissGestureRef?: RefObject<GestureType | undefined>;
  onContentSizeChange?: (width: number, height: number) => void;
  onEditTranscript: (value: string | null) => void;
  onChangeTranscript: (value: string) => void;
  onSubmitTranscript: () => void;
  onUseKeyboard: () => void;
  onDiscardRecording: () => void;
  onRetry: () => void;
  onConfirmProposal: (proposalId: string) => void;
  onResolveProposal: (proposalId: string, choice: ClarificationChoice) => void;
  onReact?: (responseId: string, reaction: ResponseReaction) => void;
  onShareExample?: (responseId: string) => void;
}

interface RevealableTaisaReplyProps {
  message: ChatMessage;
  reaction: ResponseReaction | null;
  onReact?: (responseId: string, reaction: ResponseReaction) => void;
  onShareExample?: (responseId: string) => void;
}

class RevealableTaisaReply extends Component<RevealableTaisaReplyProps, { visible: boolean }> {
  state = { visible: false };

  render() {
    const { message, reaction, onReact, onShareExample } = this.props;
    return (
      <TaisaReplyCard
        appearance="plain"
        responseId={message.id}
        content={message.content}
        reaction={reaction}
        onReact={onReact}
        onShareExample={onShareExample}
        showRatingOptions={this.state.visible}
        onShowRatingOptions={() => this.setState({ visible: true })}
      />
    );
  }
}

export function ChatConversationSurface(props: ChatConversationSurfaceProps) {
  return (
    <View className="flex-1">
      <ScrollView
        ref={props.scrollRef}
        simultaneousHandlers={props.dismissGestureRef}
        bounces={false}
        alwaysBounceVertical={false}
        className="flex-1"
        contentContainerStyle={{ paddingTop: 8, paddingBottom: 40 }}
        showsVerticalScrollIndicator={false}
        onScroll={(event) => props.onScrollAtTopChange?.(event.nativeEvent.contentOffset.y <= 2)}
        onContentSizeChange={props.onContentSizeChange}
        scrollEventThrottle={16}
      >
        {props.messages.filter((message) => message.content.length > 0).map((message) => (
          message.role === 'assistant' ? (
            <RevealableTaisaReply
              key={message.id}
              message={message}
              reaction={props.reactions?.[message.id] ?? null}
              onReact={props.onReact}
              onShareExample={props.onShareExample}
            />
          ) : (
            <ChatMessageBubble
              key={message.id}
              content={message.content}
              editable={message.id === props.activeMessageId && props.activeRequestKind === 'voice' && !props.isBusy}
              showCorrectionHint={message.id === props.activeMessageId && props.activeRequestKind === 'voice'}
              onEdit={() => props.onEditTranscript(message.content)}
            />
          )
        ))}

        {props.phase === 'processing' && props.transcript.length > 0 &&
        !props.messages.some((message) => message.id === props.activeMessageId) ? (
          <PendingTranscriptBubble transcript={props.transcript} />
          ) : null}

        {props.editingTranscript !== null ? (
          <TranscriptCorrectionCard
            value={props.editingTranscript}
            disabled={props.isBusy}
            onChangeText={props.onChangeTranscript}
            onCancel={() => props.onEditTranscript(null)}
            onSubmit={props.onSubmitTranscript}
          />
        ) : null}

        {props.phase === 'processing' ? <ChatProcessingBubble /> : null}

        {props.phase === 'error' ? (
          <ChatErrorPanel
            message={props.microphoneUnavailable
              ? 'The microphone is unavailable. Finish the active call or use the keyboard.'
              : props.error ?? 'Taisa could not complete this action. Your content remains on this device.'}
            microphoneUnavailable={props.microphoneUnavailable}
            voiceRequest={props.activeRequestKind === 'voice'}
            disabled={props.isBusy}
            onUseKeyboard={props.onUseKeyboard}
            onDiscardRecording={props.onDiscardRecording}
            onRetry={props.onRetry}
          />
        ) : null}

        {props.pendingProposals.map((proposal) => (
          <PendingProposalCard
            key={proposal.id}
            proposal={proposal}
            disabled={props.isBusy}
            onConfirm={props.onConfirmProposal}
            onResolve={props.onResolveProposal}
          />
        ))}
      </ScrollView>
      <LinearGradient
        colors={[colors.backgroundTransparent, colors.background]}
        style={{ position: 'absolute', bottom: 0, left: 0, right: 0, height: 48, pointerEvents: 'none' }}
      />
    </View>
  );
}

export interface ChatComposerDockProps {
  phase: ChatPhase;
  bottomInset: number;
  children: ReactNode;
}

export function ChatComposerDock({ phase, bottomInset, children }: ChatComposerDockProps) {
  return phase === 'transcribing' || phase === 'processing' ? (
    <View className="h-30 items-center justify-center" style={{ paddingBottom: bottomInset + 12 }}>
      <Text className="text-text-tertiary text-small-regular">
        {phase === 'transcribing' ? 'Transcribing…' : 'Taisa is thinking…'}
      </Text>
    </View>
  ) : (
    <LinearGradient
      colors={[colors.backgroundTransparent, colors.background]}
      style={{ paddingTop: 8, paddingBottom: bottomInset + 12 }}
    >
      {children}
    </LinearGradient>
  );
}

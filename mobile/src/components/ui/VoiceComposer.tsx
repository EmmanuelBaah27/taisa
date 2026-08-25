import { useEffect, useReducer, useRef } from 'react';
import { Text, TextInput, View } from 'react-native';
import type { SharedValue } from 'react-native-reanimated';
import Animated, {
  Easing,
  runOnJS,
  useAnimatedStyle,
  useSharedValue,
  withTiming,
} from 'react-native-reanimated';

import { Icon } from './Icon';
import { LiquidGlassPressable } from './LiquidGlassPressable';
import { VoiceDraftStrip } from './VoiceDraftStrip';
import { colors } from '../../constants/theme';
import type { VoiceDraftState } from '../../services/voiceComposerState';
import { reduceVoiceComposerTransition } from './voiceComposerTransition';

export interface VoiceComposerProps {
  mode: 'voice' | 'text';
  voiceState: VoiceDraftState;
  durationSeconds: number;
  amplitude: SharedValue<number>;
  text: string;
  hasVoiceDraft: boolean;
  submissionFailed: boolean;
  recordingStartFailed: boolean;
  textFocusRequest: number;
  disabled?: boolean;
  recordingActionDisabled?: boolean;
  transcribing?: boolean;
  cancelVoiceLabel: string;
  onChangeText: (value: string) => void;
  onSwitchToText: () => void;
  onSwitchToVoice: () => void;
  onStartVoice: () => void;
  onPause: () => void;
  onResume: () => void;
  onCancelVoice: () => void;
  onDeleteText: () => void;
  onDeleteVoice: () => void;
  onSend: () => void;
}

function formatDuration(seconds: number): string {
  const whole = Math.max(0, Math.floor(seconds));
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`;
}

export function VoiceComposer(props: VoiceComposerProps) {
  const textInputRef = useRef<TextInput>(null);
  const [replyTransition, dispatchReplyTransition] = useReducer(reduceVoiceComposerTransition, 'idle');
  const replyOpacity = useSharedValue(1);
  const replyScale = useSharedValue(1);

  const replyAnimatedStyle = useAnimatedStyle(() => ({
    opacity: replyOpacity.value,
    transform: [{ scale: replyScale.value }],
  }));

  useEffect(() => {
    if (props.mode === 'text' && props.textFocusRequest > 0) {
      textInputRef.current?.focus();
    }
  }, [props.mode, props.textFocusRequest]);

  useEffect(() => {
    if (props.voiceState === 'ready' || replyTransition !== 'recording') return;
    replyOpacity.value = 1;
    replyScale.value = 1;
    dispatchReplyTransition('reset');
  }, [props.voiceState, replyOpacity, replyScale, replyTransition]);

  useEffect(() => {
    if (!props.recordingStartFailed || replyTransition !== 'recording') return;
    replyOpacity.value = 1;
    replyScale.value = 1;
    dispatchReplyTransition('start-failed');
  }, [props.recordingStartFailed, replyOpacity, replyScale, replyTransition]);

  function completeReplyExit() {
    dispatchReplyTransition('exit-complete');
    props.onStartVoice();
  }

  function startVoiceAfterReplyExit() {
    if (replyTransition !== 'idle') return;
    dispatchReplyTransition('press');
    replyOpacity.value = withTiming(0, {
      duration: 160,
      easing: Easing.out(Easing.cubic),
    });
    replyScale.value = withTiming(0.88, {
      duration: 160,
      easing: Easing.out(Easing.cubic),
    }, (finished) => {
      if (finished) runOnJS(completeReplyExit)();
    });
  }

  if (props.submissionFailed) return null;

  if (props.mode === 'text') {
    const hasText = props.text.trim().length > 0;
    return (
      <View>
        {props.transcribing ? (
          <Text className="text-center text-text-tertiary text-caption-regular">Transcribing…</Text>
        ) : null}
        <View
          className="min-h-[100px] rounded-[28px] border border-border bg-background p-3"
          style={{
            shadowColor: colors.shadowSubtle,
            shadowOffset: { width: 0, height: 8 },
            shadowOpacity: 0.12,
            shadowRadius: 20,
          }}
        >
          <TextInput
            ref={textInputRef}
            value={props.text}
            onChangeText={props.onChangeText}
            editable={!props.disabled}
            placeholder="Ask follow-up"
            multiline
            className="min-h-6 max-h-[120px] pb-12 text-foreground text-base-regular"
          />
          <LiquidGlassPressable
            accessibilityLabel={hasText ? 'Send message' : 'Start recording'}
            hierarchy="prominent"
            tone="accent"
            shape="circle"
            disabled={props.disabled}
            onPress={hasText ? props.onSend : props.onStartVoice}
            className="absolute bottom-3 right-3 h-10 w-10"
          >
            <Icon name={hasText ? 'IconArrowUp' : 'IconVoiceMid'} size={20} color={colors.textPrimary} />
          </LiquidGlassPressable>
        </View>
      </View>
    );
  }

  if (props.voiceState === 'ready') {
    return (
      <Animated.View
        className="self-center"
        style={replyAnimatedStyle}
        pointerEvents={replyTransition === 'idle' ? 'auto' : 'none'}
      >
        <LiquidGlassPressable
          accessibilityLabel="Reply by voice, starts recording"
          disabled={props.disabled || replyTransition !== 'idle'}
          onPress={startVoiceAfterReplyExit}
          className="h-14 px-12"
          contentClassName="flex-1 flex-row items-center justify-center gap-2"
        >
          <Icon name="IconVoiceMid" size={20} color={colors.textPrimary} />
          <Text className="text-foreground text-base-semibold">Reply</Text>
        </LiquidGlassPressable>
      </Animated.View>
    );
  }

  const paused = props.voiceState === 'paused';

  return (
    <View className="gap-3">
      {props.text.trim() ? (
        <VoiceDraftStrip label="Text draft" preview={props.text} onOpen={props.onSwitchToText} onDelete={props.onDeleteText} />
      ) : null}
      <View className="flex-row items-center justify-between">
        {paused ? (
          <LiquidGlassPressable
            accessibilityLabel={props.cancelVoiceLabel}
            disabled={props.disabled}
            onPress={props.onCancelVoice}
            shape="circle"
            className="h-14 w-14"
          >
            <Icon name="IconCrossMedium" size={24} color={colors.textPrimary} />
          </LiquidGlassPressable>
        ) : (
          <View className="flex-row items-center gap-3">
            <LiquidGlassPressable
              accessibilityLabel={props.cancelVoiceLabel}
              disabled={props.disabled}
              onPress={props.onCancelVoice}
              shape="circle"
              className="h-14 w-14"
            >
              <Icon name="IconCrossMedium" size={24} color={colors.textPrimary} />
            </LiquidGlassPressable>
            <LiquidGlassPressable
              accessibilityLabel="Switch to keyboard"
              disabled={props.disabled}
              onPress={props.onSwitchToText}
              shape="circle"
              className="h-14 w-14"
            >
              <Icon name="IconKeyboardUp" size={24} color={colors.textPrimary} />
            </LiquidGlassPressable>
          </View>
        )}

        {!paused ? (
          <Text className="w-[60px] text-center text-small-regular text-muted-foreground">
            {formatDuration(props.durationSeconds)}
          </Text>
        ) : null}

        <View className={paused ? 'flex-row items-center gap-2' : 'flex-row items-center gap-[14px]'}>
          {paused ? (
            <LiquidGlassPressable
              accessibilityLabel={`Resume recording, ${formatDuration(props.durationSeconds)}`}
              disabled={props.disabled || props.recordingActionDisabled}
              onPress={props.onResume}
              className="h-14 px-4"
              contentClassName="flex-1 flex-row items-center justify-center gap-2"
            >
              <Icon name="IconArrowTriangleRight" size={24} color={colors.textPrimary} />
              <Text className="text-foreground text-base-medium">Resume</Text>
              <Text className="text-muted-foreground text-small-regular">{formatDuration(props.durationSeconds)}</Text>
            </LiquidGlassPressable>
          ) : (
            <LiquidGlassPressable
              accessibilityLabel="Pause recording"
              disabled={props.disabled || props.recordingActionDisabled}
              onPress={props.onPause}
              shape="circle"
              className="h-14 w-14"
            >
              <Icon name="IconPause" size={24} color={colors.textPrimary} />
            </LiquidGlassPressable>
          )}

          <LiquidGlassPressable
            accessibilityLabel="Send recording"
            hierarchy="prominent"
            tone="accent"
            shape="circle"
            disabled={props.disabled || props.recordingActionDisabled}
            onPress={props.onSend}
            className="h-14 w-14"
          >
            <Icon name="IconArrowUp" size={24} color={colors.textPrimary} />
          </LiquidGlassPressable>
        </View>
      </View>
    </View>
  );
}

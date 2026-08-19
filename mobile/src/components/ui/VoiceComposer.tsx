import { useEffect, useReducer, useRef } from 'react';
import { Text, TextInput, TouchableOpacity, View } from 'react-native';
import type { SharedValue } from 'react-native-reanimated';
import Animated, {
  Easing,
  runOnJS,
  useAnimatedStyle,
  useSharedValue,
  withTiming,
} from 'react-native-reanimated';

import { Icon } from './Icon';
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
  transcribing?: boolean;
  onChangeText: (value: string) => void;
  onSwitchToText: () => void;
  onSwitchToVoice: () => void;
  onStartVoice: () => void;
  onPause: () => void;
  onResume: () => void;
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
    return (
      <View className="gap-2">
        {props.transcribing ? (
          <Text className="text-center text-text-tertiary text-caption-regular">Transcribing…</Text>
        ) : null}
        <TouchableOpacity
          accessibilityLabel={props.hasVoiceDraft
            ? `Open voice draft, ${formatDuration(props.durationSeconds)}`
            : 'Switch to voice and start recording'}
          disabled={props.disabled}
          onPress={props.hasVoiceDraft ? props.onSwitchToVoice : props.onStartVoice}
          className="h-10 self-start flex-row items-center gap-2 rounded-full bg-subtle px-4"
        >
          <Icon name="IconVoiceMid" size={18} color={colors.textPrimary} />
          {props.hasVoiceDraft ? (
            <Text className="text-foreground text-small-semibold">
              {formatDuration(props.durationSeconds)}
            </Text>
          ) : null}
        </TouchableOpacity>
        <View className="min-h-14 flex-row items-end gap-2 rounded-full border border-border bg-background p-1.5 pl-4">
          <TextInput
            ref={textInputRef}
            value={props.text}
            onChangeText={props.onChangeText}
            editable={!props.disabled}
            placeholder="Write something…"
            multiline
            className="max-h-32 min-h-10 flex-1 py-2 text-foreground text-base-regular"
          />
          <TouchableOpacity disabled={props.disabled} onPress={props.onSend} className="h-10 w-10 items-center justify-center rounded-full bg-muted">
            <Icon name="IconArrowUp" size={18} color={colors.textPrimary} />
          </TouchableOpacity>
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
        <TouchableOpacity
          accessibilityLabel="Reply by voice, starts recording"
          accessibilityRole="button"
          accessibilityState={{ disabled: props.disabled || replyTransition !== 'idle' }}
          disabled={props.disabled || replyTransition !== 'idle'}
          onPress={startVoiceAfterReplyExit}
          className="h-14 flex-row items-center justify-center gap-2 rounded-full border border-border-subtle bg-background px-12 shadow-xs"
        >
          <Icon name="IconVoiceMid" size={20} color={colors.textPrimary} />
          <Text className="text-foreground text-base-semibold">Reply</Text>
        </TouchableOpacity>
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
          <TouchableOpacity
            accessibilityLabel="Delete recording"
            accessibilityRole="button"
            disabled={props.disabled}
            onPress={props.onDeleteVoice}
            className="h-14 w-14 items-center justify-center rounded-full border border-border-subtle bg-background shadow-sm"
          >
            <Icon name="IconCrossMedium" size={24} color={colors.textPrimary} />
          </TouchableOpacity>
        ) : (
          <View className="flex-row items-center gap-3">
            <TouchableOpacity
              accessibilityLabel="Switch to keyboard"
              accessibilityRole="button"
              disabled={props.disabled}
              onPress={props.onSwitchToText}
              className="h-14 w-14 items-center justify-center rounded-full border border-border-subtle bg-background shadow-sm"
            >
              <Icon name="IconKeyboardUp" size={24} color={colors.textPrimary} />
            </TouchableOpacity>
            <Text className="w-[60px] text-center text-small-regular text-muted-foreground">
              {formatDuration(props.durationSeconds)}
            </Text>
          </View>
        )}

        <View className={paused ? 'flex-row items-center gap-2' : 'flex-row items-center gap-[14px]'}>
          {paused ? (
            <TouchableOpacity
              accessibilityLabel={`Resume recording, ${formatDuration(props.durationSeconds)}`}
              accessibilityRole="button"
              disabled={props.disabled}
              onPress={props.onResume}
              className="h-14 flex-row items-center gap-2 rounded-full border border-border-subtle bg-background px-4 shadow-sm"
            >
              <Icon name="IconArrowTriangleRight" size={24} color={colors.textPrimary} />
              <Text className="text-foreground text-base-medium">Resume</Text>
              <Text className="text-muted-foreground text-small-regular">{formatDuration(props.durationSeconds)}</Text>
            </TouchableOpacity>
          ) : (
            <TouchableOpacity
              accessibilityLabel="Pause recording"
              accessibilityRole="button"
              disabled={props.disabled}
              onPress={props.onPause}
              className="h-14 w-14 items-center justify-center rounded-full border border-border-subtle bg-background shadow-sm"
            >
              <Icon name="IconPause" size={24} color={colors.textPrimary} />
            </TouchableOpacity>
          )}

          <TouchableOpacity
            accessibilityLabel="Send recording"
            accessibilityRole="button"
            disabled={props.disabled}
            onPress={props.onSend}
            className={paused
              ? 'h-14 w-14 items-center justify-center rounded-full bg-primary shadow-sm'
              : 'h-14 w-14 items-center justify-center rounded-full bg-primary'}
          >
            <Icon name="IconArrowUp" size={24} color={colors.textPrimary} />
          </TouchableOpacity>
        </View>
      </View>
    </View>
  );
}

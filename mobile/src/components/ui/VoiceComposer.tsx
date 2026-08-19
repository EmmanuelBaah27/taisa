import { useEffect, useRef } from 'react';
import { Text, TextInput, TouchableOpacity, View } from 'react-native';
import type { SharedValue } from 'react-native-reanimated';
import Animated, { useAnimatedStyle } from 'react-native-reanimated';

import { Icon } from './Icon';
import { VoiceDraftStrip } from './VoiceDraftStrip';
import { colors } from '../../constants/theme';
import type { VoiceDraftState } from '../../services/voiceComposerState';

export interface VoiceComposerProps {
  mode: 'voice' | 'text';
  voiceState: VoiceDraftState;
  durationSeconds: number;
  amplitude: SharedValue<number>;
  text: string;
  hasVoiceDraft: boolean;
  submissionFailed: boolean;
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

function WaveBar({ amplitude, factor, paused }: {
  amplitude: SharedValue<number>;
  factor: number;
  paused: boolean;
}) {
  const style = useAnimatedStyle(() => ({
    height: paused ? 5 : 5 + Math.max(0, Math.min(1, amplitude.value)) * factor,
    opacity: paused ? 0.3 : 1,
  }));
  return <Animated.View className="w-0.5 rounded-full bg-foreground" style={style} />;
}

function Waveform({ paused, amplitude }: { paused: boolean; amplitude: SharedValue<number> }) {
  return (
    <View className="h-10 flex-1 flex-row items-center justify-center gap-1 rounded-full bg-subtle">
      {[9, 17, 27, 14].map((factor, index) => <WaveBar key={`l-${index}`} amplitude={amplitude} factor={factor} paused={paused} />)}
      <View className="mx-1 rounded-full bg-background p-1">
        <View className="h-8 min-w-8 items-center justify-center rounded-full bg-foreground px-2">
          <Text className="text-background text-caption-semibold">{paused ? '● Resume' : 'Ⅱ'}</Text>
        </View>
      </View>
      {[14, 27, 17, 9].map((factor, index) => <WaveBar key={`r-${index}`} amplitude={amplitude} factor={factor} paused={paused} />)}
    </View>
  );
}

export function VoiceComposer(props: VoiceComposerProps) {
  const textInputRef = useRef<TextInput>(null);

  useEffect(() => {
    if (props.mode === 'text' && props.textFocusRequest > 0) {
      textInputRef.current?.focus();
    }
  }, [props.mode, props.textFocusRequest]);

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
      <TouchableOpacity
        accessibilityLabel="Reply by voice, starts recording"
        accessibilityRole="button"
        disabled={props.disabled}
        onPress={props.onStartVoice}
        className="h-14 self-center flex-row items-center justify-center gap-2 rounded-full border border-border-subtle bg-background px-12 shadow-xs"
      >
        <Icon name="IconVoiceMid" size={20} color={colors.textPrimary} />
        <Text className="text-foreground text-base-semibold">Reply</Text>
      </TouchableOpacity>
    );
  }

  const paused = props.voiceState === 'paused';

  return (
    <View>
      {props.text.trim() ? (
        <VoiceDraftStrip label="Text draft" preview={props.text} onOpen={props.onSwitchToText} onDelete={props.onDeleteText} />
      ) : null}
      <Text className="mb-1 text-center text-text-tertiary text-caption-regular">{paused ? 'Paused' : 'Recording'} · {formatDuration(props.durationSeconds)}</Text>
      <View className="h-14 flex-row items-center gap-2 rounded-full border border-border bg-background p-1.5">
        <TouchableOpacity
          accessibilityLabel={paused ? 'Delete recording' : 'Switch to keyboard'}
          onPress={paused ? props.onDeleteVoice : props.onSwitchToText}
          className="h-10 w-10 items-center justify-center rounded-full bg-subtle"
        >
          <Icon name={paused ? 'IconX' : 'IconKeyboard'} size={18} color={colors.textPrimary} />
        </TouchableOpacity>
        <TouchableOpacity className="flex-1" onPress={paused ? props.onResume : props.onPause}>
          <Waveform paused={paused} amplitude={props.amplitude} />
        </TouchableOpacity>
        <TouchableOpacity disabled={props.disabled} onPress={props.onSend} className="h-10 w-10 items-center justify-center rounded-full bg-muted">
          <Icon name="IconArrowUp" size={18} color={colors.textPrimary} />
        </TouchableOpacity>
      </View>
    </View>
  );
}

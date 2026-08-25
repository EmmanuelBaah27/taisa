import { Text, View } from 'react-native';

import { colors } from '../../constants/theme';
import { Button } from './Button';
import { Icon } from './Icon';
import { RecordingVoiceMark } from './RecordingVoiceMark';
import { SecondaryIconButton } from './SecondaryIconButton';
import { VoiceReactiveTimestamp } from './VoiceReactiveTimestamp';

const GREETING_TEXT_STYLE = {
  fontSize: 18,
  lineHeight: 24,
  letterSpacing: -0.36,
} as const;

export interface ActiveRecordingContentProps {
  greeting: string;
}

export function ActiveRecordingContent({ greeting }: ActiveRecordingContentProps) {
  return (
    <View className="flex-1 items-center justify-center gap-6">
      <RecordingVoiceMark />
      <Text className="font-sans text-center text-muted-foreground" style={GREETING_TEXT_STYLE}>
        {greeting}
      </Text>
    </View>
  );
}

export interface ActiveRecordingActionBarProps {
  durationSeconds: number;
  amplitudeLevel: number;
  paused: boolean;
  disabled?: boolean;
  recordingActionDisabled?: boolean;
  cancelLabel: string;
  onCancel: () => void;
  onKeyboard: () => void;
  onPauseResume: () => void;
  onSend: () => void;
}

export function ActiveRecordingActionBar({
  durationSeconds,
  amplitudeLevel,
  paused,
  disabled,
  recordingActionDisabled,
  cancelLabel,
  onCancel,
  onKeyboard,
  onPauseResume,
  onSend,
}: ActiveRecordingActionBarProps) {
  return (
    <View className="flex-row items-center justify-between">
      <View className="flex-row items-center gap-3">
        <SecondaryIconButton
          label={cancelLabel}
          icon="IconCrossMedium"
          disabled={disabled}
          onPress={onCancel}
        />
        <SecondaryIconButton
          label="Switch to keyboard"
          icon="IconKeyboardUp"
          disabled={disabled}
          onPress={onKeyboard}
        />
      </View>

      <VoiceReactiveTimestamp
        durationSeconds={durationSeconds}
        amplitudeLevel={amplitudeLevel}
        paused={paused}
      />

      <View className="flex-row items-center gap-[14px]">
        <SecondaryIconButton
          label={paused ? 'Resume recording' : 'Pause recording'}
          icon={paused ? 'IconArrowTriangleRight' : 'IconPause'}
          disabled={disabled || recordingActionDisabled}
          onPress={onPauseResume}
        />
        <Button
          variant="primary"
          size="icon-lg"
          label="Send recording"
          icon={<Icon name="IconArrowUp" size={24} color={colors.secondaryActionIcon} />}
          disabled={disabled || recordingActionDisabled}
          onPress={onSend}
        />
      </View>
    </View>
  );
}

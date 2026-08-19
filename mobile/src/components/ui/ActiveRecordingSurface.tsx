import { Text, View } from 'react-native';

import { colors } from '../../constants/theme';
import { Button } from './Button';
import { Icon } from './Icon';
import { RecordingVoiceMark } from './RecordingVoiceMark';
import { SecondaryIconButton } from './SecondaryIconButton';
import { VoiceReactiveTimestamp } from './VoiceReactiveTimestamp';
import type { SharedValue } from 'react-native-reanimated';

export interface ActiveRecordingSurfaceProps {
  topInset: number;
  bottomInset: number;
  title: string;
  greeting: string;
  durationSeconds: number;
  amplitude: SharedValue<number>;
  paused: boolean;
  disabled?: boolean;
  onClose: () => void;
  onCancel: () => void;
  onKeyboard: () => void;
  onPauseResume: () => void;
  onSend: () => void;
}

export function ActiveRecordingSurface(props: ActiveRecordingSurfaceProps) {
  return (
    <View className="flex-1 bg-background">
      <View
        className="absolute left-0 right-0 z-10 flex-row items-center justify-between px-4 py-1"
        style={{ top: props.topInset }}
      >
        <SecondaryIconButton
          label="Close recording"
          icon="IconChevronDownMedium"
          disabled={props.disabled}
          onPress={props.onClose}
        />
        <Text className="absolute left-20 right-20 text-center text-foreground text-small-medium">
          {props.title}
        </Text>
        <View className="h-14 w-14" />
      </View>

      <View className="flex-1 items-center justify-center gap-6">
        <RecordingVoiceMark />
        <Text
          className="font-sans text-center text-muted-foreground"
          style={{ fontSize: 18, lineHeight: 24, letterSpacing: -0.36 }}
        >
          {props.greeting}
        </Text>
      </View>

      <View
        className="absolute left-0 right-0 flex-row items-center justify-between px-4"
        style={{ bottom: Math.max(props.bottomInset, 20) + 20 }}
      >
        <View className="flex-row items-center gap-3">
          <SecondaryIconButton
            label="Cancel voice recording"
            icon="IconCrossMedium"
            disabled={props.disabled}
            onPress={props.onCancel}
          />
          <SecondaryIconButton
            label="Switch to keyboard"
            icon="IconKeyboardUp"
            disabled={props.disabled}
            onPress={props.onKeyboard}
          />
        </View>

        <VoiceReactiveTimestamp
          durationSeconds={props.durationSeconds}
          amplitude={props.amplitude}
          paused={props.paused}
        />

        <View className="flex-row items-center gap-[14px]">
          <SecondaryIconButton
            label={props.paused ? 'Resume recording' : 'Pause recording'}
            icon={props.paused ? 'IconArrowTriangleRight' : 'IconPause'}
            disabled={props.disabled}
            onPress={props.onPauseResume}
          />
          <Button
            variant="primary"
            size="icon-lg"
            label="Send recording"
            icon={<Icon name="IconArrowUp" size={24} color={colors.secondaryActionIcon} />}
            disabled={props.disabled}
            onPress={props.onSend}
          />
        </View>
      </View>
    </View>
  );
}

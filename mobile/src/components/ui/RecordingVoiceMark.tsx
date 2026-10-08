import { View } from 'react-native';
import Svg, { Circle, Path } from 'react-native-svg';

import { colors } from '../../constants/theme';

export const RECORDING_VOICE_MARK_PATHS = {
  left: 'M24.4282 26.8479C17.9055 28.4497 10.1559 16.8666 4.66667 16.8666',
  right: 'M7.13333 24.4666C15.1614 24.4666 20.3298 14.3333 28.3298 14.3333',
} as const;

export function RecordingVoiceMark() {
  return (
    <View accessibilityElementsHidden importantForAccessibility="no-hide-descendants" className="relative h-8 w-8">
      <Svg width={32} height={32} viewBox="0 0 32 32">
        <Circle cx={16} cy={16} r={12.3333} fill="none" stroke={colors.recordingMark} strokeWidth={2} />
        <Path d={RECORDING_VOICE_MARK_PATHS.left} fill="none" stroke={colors.recordingMark} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />
        <Path d={RECORDING_VOICE_MARK_PATHS.right} fill="none" stroke={colors.recordingMark} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />
      </Svg>
    </View>
  );
}

import { Pressable } from 'react-native';
import Animated, {
  useAnimatedStyle,
  useSharedValue,
  withSpring,
  withTiming,
} from 'react-native-reanimated';

import { colors } from '../../constants/theme';
import { Icon } from './Icon';

export interface VoiceEntryButtonProps {
  bottomInset: number;
  hidden?: boolean;
  onPress: () => void;
}

export function VoiceEntryButton({ bottomInset, hidden = false, onPress }: VoiceEntryButtonProps) {
  const scale = useSharedValue(1);
  const animatedStyle = useAnimatedStyle(() => ({
    transform: [{ scale: scale.value }],
  }));

  return (
    <Animated.View
      className="absolute left-0 right-0 z-50 items-center"
      style={[{ bottom: bottomInset + 16, opacity: hidden ? 0 : 1 }, animatedStyle]}
    >
      <Pressable
        accessibilityLabel="Start a voice conversation"
        accessibilityRole="button"
        onPress={onPress}
        onPressIn={() => { scale.value = withTiming(0.95, { duration: 80 }); }}
        onPressOut={() => { scale.value = withSpring(1, { damping: 20, stiffness: 300 }); }}
        className="rounded-full bg-primary px-11 py-4"
        style={{
          shadowColor: colors.accent,
          shadowOffset: { width: 0, height: 0 },
          shadowOpacity: 0.6,
          shadowRadius: 24,
          elevation: 10,
        }}
      >
        <Icon name="IconVoiceMid" size={24} color={colors.textPrimary} />
      </Pressable>
    </Animated.View>
  );
}

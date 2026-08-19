import { Pressable } from 'react-native';
import Animated, {
  useAnimatedStyle,
  useSharedValue,
  withSpring,
  withTiming,
} from 'react-native-reanimated';

import { colors } from '../../constants/theme';
import { getBottomNavigationLayout } from '../../navigation/bottomNavigation';
import { Icon } from './Icon';

export interface VoiceEntryButtonProps {
  bottomInset: number;
  hidden?: boolean;
  onPress: () => void;
}

export function VoiceEntryButton({ bottomInset, hidden = false, onPress }: VoiceEntryButtonProps) {
  const { recordBottom } = getBottomNavigationLayout(bottomInset);
  const scale = useSharedValue(1);
  const animatedStyle = useAnimatedStyle(() => ({
    transform: [{ scale: scale.value }],
  }));

  return (
    <Animated.View
      className="absolute left-0 right-0 z-50 items-center"
      pointerEvents={hidden ? 'none' : 'box-none'}
      style={[{ bottom: recordBottom, opacity: hidden ? 0 : 1 }, animatedStyle]}
    >
      <Pressable
        accessibilityLabel="Start a voice conversation"
        accessibilityRole="button"
        onPress={onPress}
        onPressIn={() => { scale.value = withTiming(0.95, { duration: 80 }); }}
        onPressOut={() => { scale.value = withSpring(1, { damping: 20, stiffness: 300 }); }}
        className="bg-primary px-10 py-4"
        style={{
          borderRadius: 32,
          shadowColor: colors.accent,
          shadowOffset: { width: 0, height: 0 },
          shadowOpacity: 0.35,
          shadowRadius: 20,
          elevation: 10,
        }}
      >
        <Icon name="IconVoiceMid" size={24} color={colors.textPrimary} />
      </Pressable>
    </Animated.View>
  );
}

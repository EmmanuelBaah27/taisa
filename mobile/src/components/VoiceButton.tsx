import { Pressable } from 'react-native';
import { router } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withTiming,
  withSpring,
  Easing,
} from 'react-native-reanimated';
import { Icon } from './ui/Icon';
import { colors } from '../constants/theme';

interface VoiceButtonProps {
  onPress?: () => void;
}

const easeOut = Easing.bezier(0.23, 1, 0.32, 1);

export function VoiceButton({ onPress }: VoiceButtonProps) {
  const insets = useSafeAreaInsets();
  const handlePress = onPress ?? (() => router.push('/recording'));

  const scale = useSharedValue(1);

  const animStyle = useAnimatedStyle(() => ({
    transform: [{ scale: scale.value }],
  }));

  return (
    <Animated.View
      style={[
        {
          position: 'absolute',
          bottom: insets.bottom + 16,
          left: 0,
          right: 0,
          alignItems: 'center',
          zIndex: 50,
        },
        animStyle,
      ]}
    >
      <Pressable
        onPress={handlePress}
        onPressIn={() => { scale.value = withTiming(0.93, { duration: 100, easing: easeOut }); }}
        onPressOut={() => { scale.value = withSpring(1, { damping: 20, stiffness: 300 }); }}
        style={{
          backgroundColor: '#cdec1a',
          paddingVertical: 16,
          paddingHorizontal: 44,
          borderRadius: 48,
          shadowColor: colors.accent,
          shadowOffset: { width: 0, height: 0 },
          shadowOpacity: 0.6,
          shadowRadius: 24,
          elevation: 10,
        }}
      >
        <Icon name="IconVoiceMid" size={24} color="#060707" />
      </Pressable>
    </Animated.View>
  );
}

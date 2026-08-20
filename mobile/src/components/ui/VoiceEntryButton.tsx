import { Pressable, View } from 'react-native';
import { useSharedValue, withSpring, withTiming } from 'react-native-reanimated';

import { colors } from '../../constants/theme';
import { getBottomNavigationLayout } from '../../navigation/bottomNavigation';
import { Icon } from './Icon';
import { LiquidGlassButtonSurface } from './LiquidGlassButtonSurface';

export interface VoiceEntryButtonProps {
  bottomInset: number;
  hidden?: boolean;
  onPress: () => void;
}

export function VoiceEntryButton({ bottomInset, hidden = false, onPress }: VoiceEntryButtonProps) {
  const { recordBottom } = getBottomNavigationLayout(bottomInset);
  const pressed = useSharedValue(0);

  if (hidden) return null;

  return (
    <View
      className="absolute left-0 right-0 z-50 items-center"
      style={{ bottom: recordBottom }}
      pointerEvents="box-none"
    >
      <Pressable
        accessibilityLabel="Start a voice conversation"
        accessibilityRole="button"
        onPress={onPress}
        onPressIn={() => { pressed.value = withTiming(1, { duration: 100 }); }}
        onPressOut={() => { pressed.value = withSpring(0, { damping: 24, stiffness: 360 }); }}
        style={{
          width: 104,
          height: 56,
          borderRadius: 32,
          shadowColor: colors.accent,
          shadowOffset: { width: 0, height: 0 },
          shadowOpacity: 0.35,
          shadowRadius: 20,
          elevation: 10,
        }}
      >
        <LiquidGlassButtonSurface
          hierarchy="prominent"
          tone="accent"
          shape="capsule"
          pressed={pressed}
          style={{ width: 104, height: 56, alignItems: 'center', justifyContent: 'center' }}
        >
          <Icon name="IconVoiceMid" size={24} color={colors.textPrimary} />
        </LiquidGlassButtonSurface>
      </Pressable>
    </View>
  );
}

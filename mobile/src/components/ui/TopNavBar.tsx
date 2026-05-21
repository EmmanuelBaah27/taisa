import { useEffect, useRef } from 'react';
import { View, Text, Pressable, LayoutAnimation, Platform, UIManager } from 'react-native';

if (Platform.OS === 'android') {
  UIManager.setLayoutAnimationEnabledExperimental?.(true);
}
import { router, usePathname } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withTiming,
  withSpring,
} from 'react-native-reanimated';
import { LinearGradient } from 'expo-linear-gradient';
import { Icon } from './Icon';
import type { IconName } from './Icon';
import { useScrollContext } from '../../contexts/ScrollContext';

interface NavTab {
  id: string;
  label: string;
  icon: IconName;
  path: string;
}

const TABS: NavTab[] = [
  { id: 'index',    label: 'Activity', icon: 'IconMorningBrief', path: '/'         },
  { id: 'insights', label: 'Insights', icon: 'IconAura',         path: '/insights' },
  { id: 'goals',    label: 'Goals',    icon: 'IconTargetArrow',  path: '/goals'    },
  { id: 'logs',     label: 'Logs',     icon: 'IconChatBubbles',  path: '/logs'     },
  { id: 'you',      label: 'You',      icon: 'IconPeopleCircle', path: '/you'      },
];

function TabButton({ tab, active }: { tab: NavTab; active: boolean }) {
  const scale = useSharedValue(1);
  const prevActive = useRef(active);

  if (prevActive.current !== active) {
    prevActive.current = active;
    LayoutAnimation.configureNext({
      duration: 300,
      create: { type: 'easeInEaseOut', property: 'opacity' },
      update: { type: 'easeInEaseOut' },
      delete: { type: 'easeInEaseOut', property: 'opacity' },
    });
  }

  const animStyle = useAnimatedStyle(() => ({
    transform: [{ scale: scale.value }],
  }));

  return (
    <Animated.View style={animStyle}>
      <Pressable
        onPress={() => router.navigate(tab.path as any)}
        onPressIn={() => { scale.value = withTiming(0.96, { duration: 80 }); }}
        onPressOut={() => { scale.value = withSpring(1, { damping: 20, stiffness: 300 }); }}
        className={active
          ? 'bg-muted flex-row items-center gap-2 px-4 py-2 rounded-full'
          : 'p-2'
        }
      >
        <Icon name={tab.icon} color={active ? '#060707' : '#898989'} />
        {active && (
          <Text className="text-foreground text-base-medium">{tab.label}</Text>
        )}
      </Pressable>
    </Animated.View>
  );
}

export function TopNavBar() {
  const insets = useSafeAreaInsets();
  const pathname = usePathname();
  const { isScrolled } = useScrollContext();

  const gradientOpacity = useSharedValue(0);

  useEffect(() => {
    gradientOpacity.value = withTiming(isScrolled ? 1 : 0, { duration: 150 });
  }, [isScrolled]);

  const gradientStyle = useAnimatedStyle(() => ({
    opacity: gradientOpacity.value,
  }));

  function isActive(path: string): boolean {
    if (path === '/') return pathname === '/' || pathname === '/index';
    return pathname.startsWith(path);
  }

  return (
    <View className="bg-background">
      <View
        className="flex-row items-center justify-between px-5"
        style={{ paddingTop: insets.top + 12, paddingBottom: 12 }}
      >
        {TABS.map((tab) => (
          <TabButton key={tab.id} tab={tab} active={isActive(tab.path)} />
        ))}
      </View>
      <Animated.View
        style={[{ position: 'absolute', bottom: -20, left: 0, right: 0, height: 20 }, gradientStyle]}
        pointerEvents="none"
      >
        <LinearGradient
          colors={['#ffffff', 'rgba(255,255,255,0)']}
          style={{ flex: 1 }}
        />
      </Animated.View>
    </View>
  );
}

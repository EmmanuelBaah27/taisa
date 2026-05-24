import { useEffect, useRef } from 'react';
import { View, Text, Pressable } from 'react-native';
import { router, usePathname } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withTiming,
  withSequence,
  Easing,

} from 'react-native-reanimated';
import { LinearGradient } from 'expo-linear-gradient';
import { Icon } from './Icon';
import type { IconName } from './Icon';
import { useScrollContext } from '../../contexts/ScrollContext';
import { NaviiAvatar } from './NaviiAvatar';
import { useCareerStore } from '../../stores/careerStore';

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

function TabButton({ tab, active, tabIndex, activeIndex, userId }: {
  tab: NavTab;
  active: boolean;
  tabIndex: number;
  activeIndex: number;
  userId: string | null;
}) {
  const nudgeX = useSharedValue(0);
  const scale = useSharedValue(1);
  const prevActiveIndex = useRef(-1);

  const animStyle = useAnimatedStyle(() => ({
    transform: [{ translateX: nudgeX.value }, { scale: scale.value }],
  }));

  useEffect(() => {
    const prev = prevActiveIndex.current;
    prevActiveIndex.current = activeIndex;
    if (prev < 0 || prev === activeIndex) return;

    if (active) {
      scale.value = withSequence(
        withTiming(1.06, { duration: 100, easing: Easing.out(Easing.ease) }),
        withTiming(1, { duration: 180, easing: Easing.out(Easing.ease) }),
      );
      return;
    }

    const isAdjacent = tabIndex === activeIndex - 1 || tabIndex === activeIndex + 1;
    if (!isAdjacent) return;
    const outward = tabIndex < activeIndex ? -3 : 3;
    nudgeX.value = withSequence(
      withTiming(outward, { duration: 100, easing: Easing.out(Easing.ease) }),
      withTiming(0, { duration: 180, easing: Easing.out(Easing.ease) }),
    );
  }, [activeIndex]);

  return (
    <Animated.View style={animStyle}>
      <Pressable
        onPress={() => router.navigate(tab.path as any)}
        className={active ? 'bg-muted flex-row items-center gap-2 px-4 py-2 rounded-full' : 'p-2'}
      >
        {tab.id === 'you' && userId ? (
          <NaviiAvatar seed={userId} size={22} />
        ) : (
          <Icon name={tab.icon} color={active ? '#060707' : '#898989'} />
        )}
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

  const activeIndex = TABS.findIndex((t) => isActive(t.path));
  const userId = useCareerStore((s) => s.userId);

  return (
    <View className="bg-background">
      <View
        className="flex-row items-center justify-between px-5"
        style={{ paddingTop: insets.top + 12, paddingBottom: 12 }}
      >
        {TABS.map((tab, i) => (
          <TabButton key={tab.id} tab={tab} active={isActive(tab.path)} tabIndex={i} activeIndex={activeIndex} userId={userId} />
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

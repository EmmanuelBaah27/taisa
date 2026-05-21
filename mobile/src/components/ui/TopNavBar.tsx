import { View, Text, TouchableOpacity } from 'react-native';
import { router, usePathname } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Icon } from './Icon';
import type { IconName } from './Icon';

interface NavTab {
  id: string;
  label: string;
  icon: IconName;
  path: string;
}

const TABS: NavTab[] = [
  { id: 'index',    label: 'Activity', icon: 'IconFilter2',      path: '/'         },
  { id: 'insights', label: 'Insights', icon: 'IconSun',          path: '/insights' },
  { id: 'goals',    label: 'Goals',    icon: 'IconTarget',       path: '/goals'    },
  { id: 'logs',     label: 'Logs',     icon: 'IconBubbleDots',   path: '/logs'     },
  { id: 'you',      label: 'You',      icon: 'IconCirclePerson', path: '/you'      },
];

export function TopNavBar() {
  const insets = useSafeAreaInsets();
  const pathname = usePathname();

  function isActive(path: string): boolean {
    if (path === '/') return pathname === '/' || pathname === '/index';
    return pathname.startsWith(path);
  }

  return (
    <View
      className="bg-background border-b border-border flex-row items-center justify-between px-5"
      style={{ paddingTop: insets.top + 12, paddingBottom: 12 }}
    >
      {TABS.map((tab) => {
        const active = isActive(tab.path);
        return (
          <TouchableOpacity
            key={tab.id}
            onPress={() => router.navigate(tab.path as any)}
            className={active
              ? 'bg-muted flex-row items-center gap-2 px-4 py-2 rounded-full'
              : 'p-2'
            }
            activeOpacity={0.7}
          >
            <Icon
              name={tab.icon}
              size={20}
              color={active ? '#060707' : '#898989'}
            />
            {active && (
              <Text className="text-foreground text-base-medium">{tab.label}</Text>
            )}
          </TouchableOpacity>
        );
      })}
    </View>
  );
}

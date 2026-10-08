import { View, Text, TouchableOpacity } from 'react-native';
import { useCareerStore } from '../stores/careerStore';
import { Icon } from './ui/Icon';
import { usePageHeaderPaddingTop } from '../navigation/pageSafeArea';
import { PageHeaderSurface } from './ui/PageHeaderSurface';

interface WorkspaceHeaderProps {
  subtitle: string;
}

export function WorkspaceHeader({ subtitle }: WorkspaceHeaderProps) {
  const pageHeaderPaddingTop = usePageHeaderPaddingTop();
  const profile = useCareerStore((s) => s.profile);
  const name = profile?.currentCompany || 'Workspace';

  return (
    <PageHeaderSurface variant="workspace">
      <View className="px-5 pb-2" style={{ paddingTop: pageHeaderPaddingTop }}>
        <TouchableOpacity className="flex-row items-center gap-2 mb-1" activeOpacity={0.7}>
          <Text className="text-foreground text-H1">{name}</Text>
          <Icon name="IconChevronBottom" size={18} color="#060707" />
        </TouchableOpacity>
        <Text className="text-muted-foreground text-base-regular">{subtitle}</Text>
      </View>
    </PageHeaderSurface>
  );
}

import { Pressable, View } from 'react-native';
import { useCareerStore } from '../stores/careerStore';
import { Icon } from './ui/Icon';
import { usePageHeaderPaddingTop } from '../navigation/pageSafeArea';
import { PageHeaderSurface } from './ui/PageHeaderSurface';
import { Text } from './ui/Text';

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
        <Pressable className="flex-row items-center gap-2 mb-1">
          <Text role="heading">{name}</Text>
          <Icon name="IconChevronBottom" size={18} colorRole="primary" />
        </Pressable>
        <Text color="secondary">{subtitle}</Text>
      </View>
    </PageHeaderSurface>
  );
}

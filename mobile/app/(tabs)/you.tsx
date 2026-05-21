import { useCallback, useState } from 'react';
import { View, Text, ScrollView, TouchableOpacity, TextInput, Modal } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { useCareerStore } from '../../src/stores/careerStore';
import { ThemeTag } from '../../src/components/ThemeTag';
import { WorkspaceHeader } from '../../src/components/WorkspaceHeader';
import { useScrollContext } from '../../src/contexts/ScrollContext';
import { colors } from '../../src/constants/theme';
import api from '../../src/services/api';

interface YouData {
  currentFocus: string;
  themes: string[];
  openLoops: string;
}

export default function YouScreen() {
  const { profile, fetchProfile, updateProfile } = useCareerStore();
  const { reportScroll } = useScrollContext();
  const [youData, setYouData] = useState<YouData | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [editingGoals, setEditingGoals] = useState(false);
  const [editingContext, setEditingContext] = useState(false);
  const [goalsInput, setGoalsInput] = useState('');
  const [roleInput, setRoleInput] = useState('');

  useFocusEffect(
    useCallback(() => {
      fetchProfile();
      loadYouData();
      return () => reportScroll(0);
    }, [])
  );

  const loadYouData = async () => {
    setIsLoading(true);
    try {
      const res = await api.get('/today/you');
      setYouData(res.data.data);
    } catch (e) {
      // Silent fail
    } finally {
      setIsLoading(false);
    }
  };

  const saveGoals = async () => {
    try {
      await updateProfile({ longTermGoal: goalsInput });
      setEditingGoals(false);
    } catch (e) {}
  };

  const saveContext = async () => {
    try {
      const [role, company] = roleInput.split(',').map(s => s.trim());
      await updateProfile({ currentRole: role, currentCompany: company });
      setEditingContext(false);
    } catch (e) {}
  };

  const sessionCount = profile?.totalEntryCount ?? 0;

  return (
    <View className="flex-1 bg-background">
      <WorkspaceHeader subtitle="Your career profile and preferences" />
    <ScrollView
      className="flex-1 bg-background"
      onScroll={(e) => reportScroll(e.nativeEvent.contentOffset.y)}
      scrollEventThrottle={16}
      contentContainerStyle={{ paddingHorizontal: 16, paddingTop: 8, paddingBottom: 120 }}
    >
      {/* Avatar row */}
      <View className="flex-row items-center mb-6">
        <View className="w-10 h-10 rounded-full bg-accent-muted items-center justify-center mr-3"
          style={{ borderWidth: 1.5, borderColor: 'rgba(205,236,26,0.3)' }}>
          <Text className="text-lime-700 text-lg font-bold">T</Text>
        </View>
        <View>
          <Text className="text-foreground text-sm font-bold">Taisa User</Text>
          <Text className="text-text-tertiary text-xs">{profile?.currentRole ?? 'Your role'} · {sessionCount} session{sessionCount !== 1 ? 's' : ''}</Text>
        </View>
      </View>

      {/* Taisa's read on you */}
      <SectionLabel>Taisa's read on you</SectionLabel>

      {isLoading ? (
        <View className="bg-card rounded-xl px-4 py-4 mb-2 opacity-50">
          <View className="h-2 bg-muted rounded w-1/3 mb-3" />
          <View className="h-3 bg-muted rounded w-full mb-2" />
          <View className="h-3 bg-muted rounded w-2/3" />
        </View>
      ) : (
        <>
          {youData?.currentFocus ? (
            <InfoCard label="Current focus" value={youData.currentFocus} />
          ) : null}

          {youData?.themes && youData.themes.length > 0 && (
            <View className="bg-card rounded-xl px-4 py-3 mb-2">
              <Text className="text-lime-700 text-xs font-bold uppercase tracking-wider mb-2">Recurring themes</Text>
              <View className="flex-row flex-wrap">
                {youData.themes.map(t => <ThemeTag key={t} label={t} />)}
              </View>
            </View>
          )}

          {youData?.openLoops ? (
            <InfoCard label="Open loops" value={youData.openLoops} />
          ) : null}
        </>
      )}

      {/* Career context */}
      <SectionLabel style={{ marginTop: 16 }}>Career context</SectionLabel>

      <TouchableOpacity
        className="bg-card rounded-xl px-4 py-3 mb-2 flex-row items-center"
        onPress={() => { setGoalsInput(profile?.longTermGoal ?? ''); setEditingGoals(true); }}
      >
        <Text className="text-base mr-3">🎯</Text>
        <View className="flex-1">
          <Text className="text-foreground text-sm font-semibold">Goals</Text>
          <Text className="text-text-tertiary text-xs mt-0.5" numberOfLines={2}>{profile?.longTermGoal || 'Tap to add your goals'}</Text>
        </View>
        <Text className="text-text-tertiary text-base">›</Text>
      </TouchableOpacity>

      <TouchableOpacity
        className="bg-card rounded-xl px-4 py-3 mb-2 flex-row items-center"
        onPress={() => { setRoleInput(`${profile?.currentRole ?? ''}, ${profile?.currentCompany ?? ''}`); setEditingContext(true); }}
      >
        <Text className="text-base mr-3">🏢</Text>
        <View className="flex-1">
          <Text className="text-foreground text-sm font-semibold">Role & company</Text>
          <Text className="text-text-tertiary text-xs mt-0.5">{[profile?.currentRole, profile?.currentCompany].filter(Boolean).join(', ') || 'Tap to add'}</Text>
        </View>
        <Text className="text-text-tertiary text-base">›</Text>
      </TouchableOpacity>

      {/* Settings */}
      <SectionLabel style={{ marginTop: 16 }}>Settings</SectionLabel>

      <TouchableOpacity className="bg-card rounded-xl px-4 py-3 mb-2 flex-row justify-between items-center">
        <Text className="text-foreground text-sm">Export my data</Text>
        <Text className="text-text-tertiary text-base">›</Text>
      </TouchableOpacity>

      {/* Edit modals */}
      <EditModal
        visible={editingGoals}
        title="Career goals"
        value={goalsInput}
        onChangeText={setGoalsInput}
        onSave={saveGoals}
        onDismiss={() => setEditingGoals(false)}
        placeholder="e.g. Staff promotion in 12 months, move into leadership"
        multiline
      />
      <EditModal
        visible={editingContext}
        title="Role & company"
        value={roleInput}
        onChangeText={setRoleInput}
        onSave={saveContext}
        onDismiss={() => setEditingContext(false)}
        placeholder="e.g. Senior Designer, Acme Inc"
      />
    </ScrollView>
    </View>
  );
}

function SectionLabel({ children, style }: { children: React.ReactNode; style?: object }) {
  return (
    <Text className="text-text-tertiary text-xs font-bold uppercase tracking-wider mb-2" style={style}>
      {children}
    </Text>
  );
}

function InfoCard({ label, value }: { label: string; value: string }) {
  return (
    <View className="bg-card rounded-xl px-4 py-3 mb-2">
      <Text className="text-lime-700 text-xs font-bold uppercase tracking-wider mb-1">{label}</Text>
      <Text className="text-muted-foreground text-sm leading-relaxed">{value}</Text>
    </View>
  );
}

function EditModal({ visible, title, value, onChangeText, onSave, onDismiss, placeholder, multiline }: {
  visible: boolean;
  title: string;
  value: string;
  onChangeText: (t: string) => void;
  onSave: () => void;
  onDismiss: () => void;
  placeholder?: string;
  multiline?: boolean;
}) {
  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onDismiss}>
      <View className="flex-1 justify-end" style={{ backgroundColor: 'rgba(6,7,7,0.5)' }}>
        <View className="bg-background rounded-t-3xl px-6 pt-4 pb-12">
          <View className="w-8 h-1 bg-border rounded-full self-center mb-4" />
          <Text className="text-foreground text-base font-bold mb-4">{title}</Text>
          <TextInput
            value={value}
            onChangeText={onChangeText}
            placeholder={placeholder}
            placeholderTextColor={colors.textTertiary}
            className="bg-card rounded-xl px-4 py-3 text-foreground text-sm mb-4"
            multiline={multiline}
            style={multiline ? { minHeight: 80, textAlignVertical: 'top' } : undefined}
            autoFocus
          />
          <View className="flex-row gap-3">
            <TouchableOpacity onPress={onDismiss} className="flex-1 bg-muted rounded-full py-3 items-center">
              <Text className="text-muted-foreground text-sm font-semibold">Cancel</Text>
            </TouchableOpacity>
            <TouchableOpacity onPress={onSave} className="flex-1 bg-primary rounded-full py-3 items-center">
              <Text className="text-foreground text-sm font-semibold">Save</Text>
            </TouchableOpacity>
          </View>
        </View>
      </View>
    </Modal>
  );
}

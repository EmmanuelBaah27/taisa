import { useCallback, useEffect, useRef, useState } from 'react';
import { View, Text, ScrollView, TouchableOpacity, TextInput, Modal, Share, Switch, KeyboardAvoidingView, Platform } from 'react-native';
import { File } from 'expo-file-system';
import { useFocusEffect } from 'expo-router';
import { useCareerStore } from '../../src/stores/careerStore';
import { ThemeTag } from '../../src/components/ThemeTag';
import { useScrollContext } from '../../src/contexts/ScrollContext';
import { colors } from '../../src/constants/theme';
import { NaviiAvatar } from '../../src/components/ui/NaviiAvatar';
import {
  ArchiveOperationError,
  exportEncryptedArchive,
  restoreEncryptedArchive,
} from '../../src/services/exportArchive';
import { getPrivacyGuard } from '../../src/services/privacyGuard';
import { runSingleFlight } from '../../src/services/singleFlight';
import { replaceReadableStoreAuthority } from '../../src/services/restoredStoreAuthority';
import api from '../../src/services/api';
import {
  createDeviceEnrollmentClient,
  getDeviceCredential,
} from '../../src/services/deviceEnrollment';

interface YouData {
  currentFocus: string;
  themes: string[];
  openLoops: string;
}

type RecoveryMode = 'export' | 'restore' | null;

export default function YouScreen() {
  const { profile, userId, fetchProfile, updateProfile } = useCareerStore();
  const { reportScroll } = useScrollContext();
  const [editingGoals, setEditingGoals] = useState(false);
  const [editingContext, setEditingContext] = useState(false);
  const [goalsInput, setGoalsInput] = useState('');
  const [roleInput, setRoleInput] = useState('');
  const privacyGuard = getPrivacyGuard();
  const [privacyState, setPrivacyState] = useState(privacyGuard.getState());
  const [recoveryMode, setRecoveryMode] = useState<RecoveryMode>(null);
  const [selectedArchiveUri, setSelectedArchiveUri] = useState<string | null>(null);
  const [archivePassphrase, setArchivePassphrase] = useState('');
  const [archiveConfirmation, setArchiveConfirmation] = useState('');
  const [archiveBusy, setArchiveBusy] = useState(false);
  const [privacyNotice, setPrivacyNotice] = useState<string | null>(null);
  const [enrollmentCode, setEnrollmentCode] = useState('');
  const [deviceEnrolled, setDeviceEnrolled] = useState(false);
  const [enrollmentBusy, setEnrollmentBusy] = useState(false);
  const archiveOperationRef = useRef<Promise<void> | null>(null);

  useEffect(() => privacyGuard.subscribe(setPrivacyState), [privacyGuard]);

  useFocusEffect(
    useCallback(() => {
      fetchProfile();
      void getDeviceCredential().then((credential) => setDeviceEnrolled(credential !== null));
      return () => reportScroll(0);
    }, [])
  );

  const enrollThisDevice = async () => {
    const code = enrollmentCode;
    if (!code.trim() || enrollmentBusy) return;
    setEnrollmentBusy(true);
    setPrivacyNotice(null);
    setEnrollmentCode('');
    try {
      await createDeviceEnrollmentClient(api).enroll(code);
      setDeviceEnrolled(true);
      setPrivacyNotice('This iPhone can now connect securely to your private Taisa service.');
    } catch {
      setPrivacyNotice('The enrollment code is invalid, expired, or has already been used.');
    } finally {
      setEnrollmentBusy(false);
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

  const resetRecoveryModal = () => {
    setRecoveryMode(null);
    setSelectedArchiveUri(null);
    setArchivePassphrase('');
    setArchiveConfirmation('');
  };

  const chooseArchiveToRestore = async () => {
    try {
      const selected = await File.pickFileAsync(undefined, 'application/octet-stream');
      const file = Array.isArray(selected) ? selected[0] : selected;
      if (!file) return;
      setSelectedArchiveUri(file.uri);
      setRecoveryMode('restore');
      setPrivacyNotice(null);
    } catch {
      // Closing the system picker is a complete, no-op outcome.
    }
  };

  const runRecoveryAction = () => runSingleFlight(archiveOperationRef, async () => {
    const mode = recoveryMode;
    const selectedUri = selectedArchiveUri;
    const passphrase = archivePassphrase;
    const confirmation = archiveConfirmation;
    if (mode === null) return;

    setArchiveBusy(true);
    setPrivacyNotice(null);
    // React Native strings cannot be zeroized, but the UI and retained state release both secrets
    // as soon as the operation has captured its immutable local values.
    setArchivePassphrase('');
    setArchiveConfirmation('');
    try {
      if (mode === 'export') {
        const result = await exportEncryptedArchive(passphrase, confirmation);
        await Share.share({
          title: 'Save encrypted Taisa backup',
          url: result.uri,
        });
        setPrivacyNotice('Encrypted backup created. Keep the passphrase somewhere separate.');
      } else {
        if (selectedUri === null) return;
        await restoreEncryptedArchive(selectedUri, passphrase);
        await replaceReadableStoreAuthority();
        setPrivacyNotice('Encrypted backup restored and verified.');
      }
      resetRecoveryModal();
    } catch (error) {
      setPrivacyNotice(error instanceof ArchiveOperationError
        ? error.message
        : 'The archive operation could not be completed safely.');
    } finally {
      setArchivePassphrase('');
      setArchiveConfirmation('');
      setArchiveBusy(false);
    }
  });

  const toggleAppLock = async (enabled: boolean) => {
    setPrivacyNotice(null);
    try {
      await privacyGuard.setLockEnabled(enabled);
      if (enabled) await privacyGuard.unlock();
    } catch {
      setPrivacyNotice('Face ID or device authentication is not available and enrolled.');
    }
  };

  const sessionCount = profile?.totalEntryCount ?? 0;
  const youData: YouData = {
    currentFocus: profile?.currentFocusArea ?? '',
    themes: profile?.dominantThemes ?? [],
    openLoops: '',
  };

  return (
    <View className="flex-1 bg-background">
      <Text className="text-foreground text-H1 px-5 pt-3 pb-3">You</Text>
    <ScrollView
      className="flex-1 bg-background"
      onScroll={(e) => reportScroll(e.nativeEvent.contentOffset.y)}
      scrollEventThrottle={16}
      contentContainerStyle={{ paddingHorizontal: 16, paddingTop: 8, paddingBottom: 120 }}
    >
      {/* Avatar row */}
      <View className="items-center mb-6">
        {userId ? (
          <NaviiAvatar seed={userId} size={64} />
        ) : (
          <View className="w-16 h-16 rounded-full bg-accent-muted items-center justify-center"
            style={{ borderWidth: 1.5, borderColor: 'rgba(205,236,26,0.3)' }}>
            <Text className="text-lime-700 text-xl font-bold">T</Text>
          </View>
        )}
        <Text className="text-foreground text-sm font-bold mt-2">Taisa User</Text>
        <Text className="text-text-tertiary text-xs mt-0.5">{profile?.currentRole ?? 'Your role'} · {sessionCount} session{sessionCount !== 1 ? 's' : ''}</Text>
      </View>

      {/* Taisa's read on you */}
      <SectionLabel>Taisa's read on you</SectionLabel>

      {youData.currentFocus ? (
        <InfoCard label="Current focus" value={youData.currentFocus} />
      ) : null}

      {youData.themes.length > 0 && (
        <View className="bg-card rounded-xl px-4 py-3 mb-2">
          <Text className="text-lime-700 text-xs font-bold uppercase tracking-wider mb-2">Recurring themes</Text>
          <View className="flex-row flex-wrap">
            {youData.themes.map(t => <ThemeTag key={t} label={t} />)}
          </View>
        </View>
      )}

      {youData.openLoops ? (
        <InfoCard label="Open loops" value={youData.openLoops} />
      ) : null}

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

      <View className="bg-card rounded-xl px-4 py-3 mb-2">
        <Text className="text-foreground text-sm font-semibold">Private service</Text>
        <Text className="text-text-tertiary text-xs mt-0.5 mb-3">
          {deviceEnrolled
            ? 'This iPhone is securely enrolled.'
            : 'Enter the one-time code from your private Taisa service.'}
        </Text>
        {!deviceEnrolled ? (
          <View className="flex-row items-center gap-2">
            <TextInput
              className="flex-1 bg-background rounded-lg px-3 py-2 text-foreground"
              value={enrollmentCode}
              onChangeText={setEnrollmentCode}
              placeholder="One-time code"
              placeholderTextColor={colors.textTertiary}
              autoCapitalize="none"
              autoCorrect={false}
              editable={!enrollmentBusy}
              returnKeyType="done"
              onSubmitEditing={() => { void enrollThisDevice(); }}
            />
            <TouchableOpacity
              className="bg-foreground rounded-lg px-4 py-2"
              disabled={enrollmentBusy || !enrollmentCode.trim()}
              onPress={() => { void enrollThisDevice(); }}
            >
              <Text className="text-background text-sm font-semibold">
                {enrollmentBusy ? 'Connecting…' : 'Connect'}
              </Text>
            </TouchableOpacity>
          </View>
        ) : null}
      </View>

      <TouchableOpacity
        className="bg-card rounded-xl px-4 py-3 mb-2 flex-row justify-between items-center"
        onPress={() => { setRecoveryMode('export'); setPrivacyNotice(null); }}
      >
        <Text className="text-foreground text-sm">Export my data</Text>
        <Text className="text-text-tertiary text-base">›</Text>
      </TouchableOpacity>

      <TouchableOpacity
        className="bg-card rounded-xl px-4 py-3 mb-2 flex-row justify-between items-center"
        onPress={() => { void chooseArchiveToRestore(); }}
      >
        <Text className="text-foreground text-sm">Restore encrypted backup</Text>
        <Text className="text-text-tertiary text-base">›</Text>
      </TouchableOpacity>

      <View className="bg-card rounded-xl px-4 py-3 mb-2 flex-row justify-between items-center">
        <View className="flex-1 pr-4">
          <Text className="text-foreground text-sm">Require device unlock</Text>
          <Text className="text-text-tertiary text-xs mt-0.5">Optional Face ID or device authentication</Text>
        </View>
        <Switch
          value={privacyState.lockEnabled}
          onValueChange={(enabled) => { void toggleAppLock(enabled); }}
        />
      </View>

      {privacyNotice ? (
        <Text className="text-text-tertiary text-xs leading-relaxed px-1 mt-1 mb-2">
          {privacyNotice}
        </Text>
      ) : null}

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
      <RecoveryModal
        mode={recoveryMode}
        passphrase={archivePassphrase}
        confirmation={archiveConfirmation}
        busy={archiveBusy}
        onChangePassphrase={setArchivePassphrase}
        onChangeConfirmation={setArchiveConfirmation}
        onConfirm={() => { void runRecoveryAction(); }}
        onDismiss={resetRecoveryModal}
      />
    </ScrollView>
    </View>
  );
}

function RecoveryModal({
  mode,
  passphrase,
  confirmation,
  busy,
  onChangePassphrase,
  onChangeConfirmation,
  onConfirm,
  onDismiss,
}: {
  mode: RecoveryMode;
  passphrase: string;
  confirmation: string;
  busy: boolean;
  onChangePassphrase: (value: string) => void;
  onChangeConfirmation: (value: string) => void;
  onConfirm: () => void;
  onDismiss: () => void;
}) {
  const exporting = mode === 'export';
  const [passphraseVisible, setPassphraseVisible] = useState(false);
  return (
    <Modal visible={mode !== null} transparent animationType="slide" onRequestClose={onDismiss}>
      <KeyboardAvoidingView
        className="flex-1 justify-end"
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        style={{ backgroundColor: 'rgba(6,7,7,0.5)' }}
      >
        <View className="bg-background rounded-t-3xl px-6 pt-4 pb-12">
          <View className="w-8 h-1 bg-border rounded-full self-center mb-4" />
          <Text className="text-foreground text-base font-bold mb-2">
            {exporting ? 'Create encrypted backup' : 'Restore encrypted backup'}
          </Text>
          <Text className="text-text-tertiary text-xs leading-relaxed mb-4">
            {exporting
              ? 'Use a separate passphrase of at least 12 characters. Taisa does not save this passphrase and cannot recover it.'
              : 'Restoring replaces the phone archive only after the backup passes integrity checks.'}
          </Text>
          <View className="bg-card rounded-xl px-4 mb-3 flex-row items-center">
            <TextInput
              value={passphrase}
              onChangeText={onChangePassphrase}
              placeholder="Backup passphrase"
              placeholderTextColor={colors.textTertiary}
              className="flex-1 py-3 text-foreground text-sm"
              secureTextEntry={!passphraseVisible}
              autoCapitalize="none"
              autoCorrect={false}
            />
            <TouchableOpacity onPress={() => setPassphraseVisible((visible) => !visible)} className="pl-3 py-3">
              <Text className="text-lime-700 text-xs font-semibold">
                {passphraseVisible ? 'Hide passphrase' : 'Show passphrase'}
              </Text>
            </TouchableOpacity>
          </View>
          {exporting ? (
            <TextInput
              value={confirmation}
              onChangeText={onChangeConfirmation}
              placeholder="Confirm backup passphrase"
              placeholderTextColor={colors.textTertiary}
              className="bg-card rounded-xl px-4 py-3 text-foreground text-sm mb-4"
              secureTextEntry={!passphraseVisible}
              autoCapitalize="none"
              autoCorrect={false}
            />
          ) : null}
          <View className="flex-row gap-3">
            <TouchableOpacity
              onPress={onDismiss}
              disabled={busy}
              className="flex-1 bg-muted rounded-full py-3 items-center"
            >
              <Text className="text-muted-foreground text-sm font-semibold">Cancel</Text>
            </TouchableOpacity>
            <TouchableOpacity
              onPress={onConfirm}
              disabled={busy}
              className="flex-1 bg-primary rounded-full py-3 items-center"
            >
              <Text className="text-foreground text-sm font-semibold">
                {busy ? 'Working…' : exporting ? 'Create backup' : 'Restore'}
              </Text>
            </TouchableOpacity>
          </View>
        </View>
      </KeyboardAvoidingView>
    </Modal>
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
      <KeyboardAvoidingView
        className="flex-1 justify-end"
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        style={{ backgroundColor: 'rgba(6,7,7,0.5)' }}
      >
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
      </KeyboardAvoidingView>
    </Modal>
  );
}

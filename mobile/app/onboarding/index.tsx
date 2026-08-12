import { useEffect, useRef, useState } from 'react';
import { View, Text, TextInput, ScrollView, TouchableOpacity, ActivityIndicator } from 'react-native';
import { router } from 'expo-router';
import * as Crypto from 'expo-crypto';
import { useCareerStore } from '../../src/stores/careerStore';
import { colors } from '../../src/constants/theme';
import {
  clearOnboardingDraft,
  loadOnboardingDraft,
  saveOnboardingDraft,
  type OnboardingFormDraft,
} from '../../src/services/onboardingDraft';

const STAGES = ['early', 'mid', 'senior', 'executive', 'founder'];
const COACHING_STYLES = ['direct', 'supportive', 'socratic', 'structured'];
const ACCOUNTABILITY = ['gentle', 'moderate', 'intense'];

export function generateLocalProfileId(): string {
  return Crypto.randomUUID();
}

export default function OnboardingScreen() {
  const { initUser, isLoading } = useCareerStore();
  const [step, setStep] = useState(0);
  const draftHydrated = useRef(false);
  const [form, setForm] = useState<OnboardingFormDraft>({
    currentRole: '',
    currentCompany: '',
    industry: '',
    yearsOfExperience: '0',
    careerStage: 'mid',
    shortTermGoal: '',
    longTermGoal: '',
    currentFocusArea: '',
    coachingStyle: 'direct',
    accountabilityLevel: 'moderate',
  });

  useEffect(() => {
    let active = true;
    void loadOnboardingDraft().then((draft) => {
      if (active && draft) {
        setStep(draft.step);
        setForm(draft.form);
      }
      draftHydrated.current = true;
    });
    return () => { active = false; };
  }, []);

  useEffect(() => {
    if (draftHydrated.current) {
      void saveOnboardingDraft({ step, form });
    }
  }, [step, form]);

  const updateForm = (key: string, value: string) => setForm(f => ({ ...f, [key]: value }));

  const handleSubmit = async () => {
    const deviceId = generateLocalProfileId();
    await initUser(deviceId, {
      ...form,
      yearsOfExperience: parseInt(form.yearsOfExperience) || 0,
    } as any);
    await clearOnboardingDraft();
    router.replace('/(tabs)');
  };

  const steps = [
    // Step 0: Career context
    <ScrollView key={0} contentContainerClassName="p-6 pb-[60px]">
      <Text className="text-[30px] font-bold text-foreground mb-2">Tell me about yourself</Text>
      <Text className="text-[13px] text-muted-foreground mb-8 leading-5">This helps your coach personalize every response.</Text>

      <Field label="Current role" placeholder="e.g. Product Manager" value={form.currentRole} onChange={v => updateForm('currentRole', v)} />
      <Field label="Company (optional)" placeholder="e.g. Acme Corp" value={form.currentCompany} onChange={v => updateForm('currentCompany', v)} />
      <Field label="Industry" placeholder="e.g. FinTech, Healthcare, Media" value={form.industry} onChange={v => updateForm('industry', v)} />
      <Field label="Years of experience" placeholder="5" value={form.yearsOfExperience} onChange={v => updateForm('yearsOfExperience', v)} keyboardType="numeric" />

      <Text className="text-[13px] font-medium text-muted-foreground mb-2">Career stage</Text>
      <View className="flex-row flex-wrap gap-2 mb-8">
        {STAGES.map(s => (
          <Pill key={s} label={s} selected={form.careerStage === s} onPress={() => updateForm('careerStage', s)} />
        ))}
      </View>

      <TouchableOpacity
        className="flex-1 py-4 rounded-full items-center bg-primary"
        style={{ opacity: form.currentRole && form.industry ? 1 : 0.5 }}
        onPress={() => setStep(1)}
        disabled={!form.currentRole || !form.industry}
      >
        <Text className="text-foreground font-semibold text-[15px]">Continue</Text>
      </TouchableOpacity>
    </ScrollView>,

    // Step 1: Goals
    <ScrollView key={1} contentContainerClassName="p-6 pb-[60px]">
      <Text className="text-[30px] font-bold text-foreground mb-2">What are you working toward?</Text>
      <Text className="text-[13px] text-muted-foreground mb-8 leading-5">Your coach uses these to keep your reflections focused.</Text>

      <Field label="Short-term goal (3-6 months)" placeholder="e.g. Get promoted to Senior PM" value={form.shortTermGoal} onChange={v => updateForm('shortTermGoal', v)} multiline />
      <Field label="Long-term vision (1-3 years)" placeholder="e.g. Lead a product org of 10+" value={form.longTermGoal} onChange={v => updateForm('longTermGoal', v)} multiline />
      <Field label="Current focus area" placeholder="e.g. Improving stakeholder communication" value={form.currentFocusArea} onChange={v => updateForm('currentFocusArea', v)} />

      <View className="flex-row mt-6">
        <TouchableOpacity className="flex-1 py-4 rounded-full items-center border border-border mr-2" onPress={() => setStep(0)}>
          <Text className="text-muted-foreground text-[15px]">Back</Text>
        </TouchableOpacity>
        <TouchableOpacity
          className="flex-1 py-4 rounded-full items-center bg-primary"
          style={{ opacity: form.shortTermGoal ? 1 : 0.5 }}
          onPress={() => setStep(2)}
          disabled={!form.shortTermGoal}
        >
          <Text className="text-foreground font-semibold text-[15px]">Continue</Text>
        </TouchableOpacity>
      </View>
    </ScrollView>,

    // Step 2: Coaching preferences
    <ScrollView key={2} contentContainerClassName="p-6 pb-[60px]">
      <Text className="text-[30px] font-bold text-foreground mb-2">How should your coach work with you?</Text>

      <Text className="text-[13px] font-medium text-muted-foreground mb-2">Coaching style</Text>
      <View className="flex-row flex-wrap gap-2 mb-8">
        {COACHING_STYLES.map(s => (
          <Pill key={s} label={s} selected={form.coachingStyle === s} onPress={() => updateForm('coachingStyle', s)} />
        ))}
      </View>

      <Text className="text-[13px] font-medium text-muted-foreground mb-2">Accountability level</Text>
      <View className="flex-row flex-wrap gap-2 mb-8">
        {ACCOUNTABILITY.map(a => (
          <Pill key={a} label={a} selected={form.accountabilityLevel === a} onPress={() => updateForm('accountabilityLevel', a)} />
        ))}
      </View>

      <View className="flex-row mt-6">
        <TouchableOpacity className="flex-1 py-4 rounded-full items-center border border-border mr-2" onPress={() => setStep(1)}>
          <Text className="text-muted-foreground text-[15px]">Back</Text>
        </TouchableOpacity>
        <TouchableOpacity className="flex-1 py-4 rounded-full items-center bg-primary" onPress={handleSubmit} disabled={isLoading}>
          {isLoading ? <ActivityIndicator color={colors.textPrimary} /> : <Text className="text-foreground font-semibold text-[15px]">Start journaling</Text>}
        </TouchableOpacity>
      </View>
    </ScrollView>,
  ];

  return (
    <View className="flex-1 bg-background">
      <View className="flex-row justify-center gap-2 pt-[60px] mb-6">
        {[0, 1, 2].map(i => (
          <View key={i} className={`w-2 h-2 rounded-full ${step >= i ? 'bg-primary' : 'bg-border'}`} />
        ))}
      </View>
      {steps[step]}
    </View>
  );
}

export function Field({ label, onChange, ...props }: { label: string; onChange?: (value: string) => void; [key: string]: any }) {
  return (
    <View className="mb-6">
      <Text className="text-[13px] font-medium text-muted-foreground mb-2">{label}</Text>
      <TextInput
        className={`bg-card rounded-xl border border-border p-4 text-foreground text-[15px] h-12${props.multiline ? ' h-20' : ''}`}
        style={props.multiline ? { textAlignVertical: 'top' } : undefined}
        placeholderTextColor={colors.textTertiary}
        onChangeText={onChange}
        {...props}
      />
    </View>
  );
}

function Pill({ label, selected, onPress }: { label: string; selected: boolean; onPress: () => void }) {
  return (
    <TouchableOpacity
      onPress={onPress}
      className={selected
        ? 'px-4 py-1 rounded-full border-2 border-primary bg-lime-100'
        : 'px-4 py-1 rounded-full border border-border bg-card'}
    >
      <Text className={selected
        ? 'text-[13px] text-primary font-semibold capitalize'
        : 'text-[13px] text-muted-foreground capitalize'}
      >
        {label}
      </Text>
    </TouchableOpacity>
  );
}

import { useEffect, useRef, useState } from 'react';
import { View, ScrollView, ActivityIndicator, KeyboardAvoidingView, Platform } from 'react-native';
import { router } from 'expo-router';
import * as Crypto from 'expo-crypto';
import { useCareerStore } from '../../src/stores/careerStore';
import { LiquidGlassPressable } from '../../src/components/ui/LiquidGlassPressable';
import { Text } from '../../src/components/ui/Text';
import { Input } from '../../src/components/ui/Input';
import { colorTokens } from '../../src/design-system/tokens';
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
      <View className="mb-2"><Text role="display">Tell me about yourself</Text></View>
      <View className="mb-8"><Text role="label" color="secondary">This helps your coach personalize every response.</Text></View>

      <Field label="Current role" placeholder="e.g. Product Manager" value={form.currentRole} onChange={v => updateForm('currentRole', v)} />
      <Field label="Company (optional)" placeholder="e.g. Acme Corp" value={form.currentCompany} onChange={v => updateForm('currentCompany', v)} />
      <Field label="Industry" placeholder="e.g. FinTech, Healthcare, Media" value={form.industry} onChange={v => updateForm('industry', v)} />
      <Field label="Years of experience" placeholder="5" value={form.yearsOfExperience} onChange={v => updateForm('yearsOfExperience', v)} keyboardType="numeric" />

      <View className="mb-2"><Text role="labelStrong" color="secondary">Career stage</Text></View>
      <View className="flex-row flex-wrap gap-2 mb-8">
        {STAGES.map(s => (
          <Pill key={s} label={s} selected={form.careerStage === s} onPress={() => updateForm('careerStage', s)} />
        ))}
      </View>

      <LiquidGlassPressable
        accessibilityLabel="Continue to goals"
        hierarchy="prominent"
        tone="accent"
        className="flex-1 py-4"
        onPress={() => setStep(1)}
        disabled={!form.currentRole || !form.industry}
      >
        <Text role="labelStrong">Continue</Text>
      </LiquidGlassPressable>
    </ScrollView>,

    // Step 1: Goals
    <ScrollView key={1} contentContainerClassName="p-6 pb-[60px]">
      <View className="mb-2"><Text role="display">What are you working toward?</Text></View>
      <View className="mb-8"><Text role="label" color="secondary">Your coach uses these to keep your reflections focused.</Text></View>

      <Field label="Short-term goal (3-6 months)" placeholder="e.g. Get promoted to Senior PM" value={form.shortTermGoal} onChange={v => updateForm('shortTermGoal', v)} multiline />
      <Field label="Long-term vision (1-3 years)" placeholder="e.g. Lead a product org of 10+" value={form.longTermGoal} onChange={v => updateForm('longTermGoal', v)} multiline />
      <Field label="Current focus area" placeholder="e.g. Improving stakeholder communication" value={form.currentFocusArea} onChange={v => updateForm('currentFocusArea', v)} />

      <View className="flex-row mt-6">
        <LiquidGlassPressable accessibilityLabel="Back to career context" className="mr-2 flex-1 py-4" onPress={() => setStep(0)}>
          <Text role="label" color="secondary">Back</Text>
        </LiquidGlassPressable>
        <LiquidGlassPressable
          accessibilityLabel="Continue to coaching preferences"
          hierarchy="prominent"
          tone="accent"
          className="flex-1 py-4"
          onPress={() => setStep(2)}
          disabled={!form.shortTermGoal}
        >
          <Text role="labelStrong">Continue</Text>
        </LiquidGlassPressable>
      </View>
    </ScrollView>,

    // Step 2: Coaching preferences
    <ScrollView key={2} contentContainerClassName="p-6 pb-[60px]">
      <View className="mb-2"><Text role="display">How should your coach work with you?</Text></View>

      <View className="mb-2"><Text role="labelStrong" color="secondary">Coaching style</Text></View>
      <View className="flex-row flex-wrap gap-2 mb-8">
        {COACHING_STYLES.map(s => (
          <Pill key={s} label={s} selected={form.coachingStyle === s} onPress={() => updateForm('coachingStyle', s)} />
        ))}
      </View>

      <View className="mb-2"><Text role="labelStrong" color="secondary">Accountability level</Text></View>
      <View className="flex-row flex-wrap gap-2 mb-8">
        {ACCOUNTABILITY.map(a => (
          <Pill key={a} label={a} selected={form.accountabilityLevel === a} onPress={() => updateForm('accountabilityLevel', a)} />
        ))}
      </View>

      <View className="flex-row mt-6">
        <LiquidGlassPressable accessibilityLabel="Back to goals" className="mr-2 flex-1 py-4" onPress={() => setStep(1)}>
          <Text role="label" color="secondary">Back</Text>
        </LiquidGlassPressable>
        <LiquidGlassPressable accessibilityLabel="Start journaling" hierarchy="prominent" tone="accent" className="flex-1 py-4" onPress={handleSubmit} disabled={isLoading}>
          {isLoading ? <ActivityIndicator color={colorTokens.text.primary} /> : <Text role="labelStrong">Start journaling</Text>}
        </LiquidGlassPressable>
      </View>
    </ScrollView>,
  ];

  return (
    <KeyboardAvoidingView
      className="flex-1 bg-background"
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <View className="flex-row justify-center gap-2 pt-[60px] mb-6">
        {[0, 1, 2].map(i => (
          <View key={i} className={`w-2 h-2 rounded-full ${step >= i ? 'bg-primary' : 'bg-border'}`} />
        ))}
      </View>
      {steps[step]}
    </KeyboardAvoidingView>
  );
}

export function Field({ label, onChange, ...props }: { label: string; onChange?: (value: string) => void; [key: string]: any }) {
  return (
    <View className="mb-6">
      <Input
        label={label}
        size="lg"
        style={props.multiline ? { height: 80 } : undefined}
        onChangeText={onChange}
        {...props}
      />
    </View>
  );
}

function Pill({ label, selected, onPress }: { label: string; selected: boolean; onPress: () => void }) {
  return (
    <LiquidGlassPressable
      accessibilityLabel={`Select ${label}`}
      onPress={onPress}
      hierarchy={selected ? 'prominent' : 'standard'}
      tone={selected ? 'accent' : 'neutral'}
      className="px-4 py-1"
    >
      <Text role={selected ? 'labelStrong' : 'label'} color={selected ? 'primary' : 'secondary'}>{label}</Text>
    </LiquidGlassPressable>
  );
}

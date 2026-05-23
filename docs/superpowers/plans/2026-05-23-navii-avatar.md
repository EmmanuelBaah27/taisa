# Navii Avatar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder "T" circle avatar on the You screen (64px, centered) and the `IconPeopleCircle` tab bar icon (22px) with a deterministic Navii mascot avatar, seeded from the device userId.

**Architecture:** A new `NaviiAvatar` component wraps `createAvatar()` from `@usenavii/core` and renders the resulting SVG string via `SvgXml` from `react-native-svg`. The device `userId` (already in SecureStore) is surfaced through `careerStore` so both the You screen and `TopNavBar` can read it synchronously.

**Tech Stack:** `@usenavii/core` (npm install needed), `react-native-svg` (already installed), Zustand (`careerStore`), NativeWind, Expo/React Native.

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Modify | `mobile/package.json` | Add `@usenavii/core` dependency |
| Modify | `mobile/src/stores/careerStore.ts` | Add `userId` field to state |
| Create | `mobile/src/components/ui/NaviiAvatar.tsx` | Seed → SVG → rendered avatar component |
| Create | `mobile/src/components/ui/NaviiAvatar.stories.tsx` | Storybook story for visual verification |
| Modify | `mobile/src/components/ui/index.ts` | Export `NaviiAvatar` |
| Modify | `mobile/app/(tabs)/you.tsx` | Replace "T" circle with 64px centered avatar |
| Modify | `mobile/src/components/ui/TopNavBar.tsx` | Replace `IconPeopleCircle` with 22px avatar |

---

## Task 1: Install @usenavii/core

**Files:**
- Modify: `mobile/package.json`

- [ ] **Step 1: Install the package**

Run from the repo root (not `mobile/` — the CLAUDE.md alias runs `npm install` from root with `--workspace`):

```bash
cd taisa-os/mobile && npm install @usenavii/core
```

Expected: `added 1 package` (or similar), no errors.

- [ ] **Step 2: Verify the installed package has a dist**

```bash
ls taisa-os/mobile/node_modules/@usenavii/core/dist/
```

Expected output includes: `index.cjs`, `index.js`, `index.d.ts`

- [ ] **Step 3: Commit**

```bash
cd taisa-os && git add mobile/package.json mobile/package-lock.json
git commit -m "chore(mobile): install @usenavii/core"
```

---

## Task 2: Add userId to careerStore

**Files:**
- Modify: `mobile/src/stores/careerStore.ts:1-46`

- [ ] **Step 1: Update the store**

Replace the full contents of `mobile/src/stores/careerStore.ts` with:

```ts
import { create } from 'zustand';
import * as SecureStore from 'expo-secure-store';
import type { CareerProfile } from '@taisa/shared';
import api from '../services/api';

interface CareerStore {
  profile: CareerProfile | null;
  userId: string | null;
  isOnboarded: boolean;
  isLoading: boolean;

  initUser: (deviceId: string, profileData: Partial<CareerProfile>) => Promise<void>;
  fetchProfile: () => Promise<void>;
  updateProfile: (data: Partial<CareerProfile>) => Promise<void>;
  setProfile: (profile: CareerProfile) => void;
}

export const useCareerStore = create<CareerStore>((set, get) => ({
  profile: null,
  userId: null,
  isOnboarded: false,
  isLoading: false,

  initUser: async (deviceId, profileData) => {
    set({ isLoading: true });
    try {
      const res = await api.post('/profile/init', { deviceId, ...profileData });
      const profile: CareerProfile = res.data.data;
      await SecureStore.setItemAsync('userId', deviceId);
      set({ profile, userId: deviceId, isOnboarded: true, isLoading: false });
    } catch (e) {
      set({ isLoading: false });
      throw e;
    }
  },

  fetchProfile: async () => {
    const [res, storedId] = await Promise.all([
      api.get('/profile'),
      SecureStore.getItemAsync('userId'),
    ]);
    set({ profile: res.data.data, userId: storedId });
  },

  updateProfile: async (data) => {
    const res = await api.put('/profile', data);
    set({ profile: res.data.data });
  },

  setProfile: (profile) => set({ profile }),
}));
```

- [ ] **Step 2: Verify TypeScript is happy**

```bash
cd taisa-os/mobile && npx tsc --noEmit 2>&1 | grep -i "careerStore\|userId" | head -10
```

Expected: no output (no errors related to these files).

- [ ] **Step 3: Commit**

```bash
cd taisa-os && git add mobile/src/stores/careerStore.ts
git commit -m "feat(store): surface userId in careerStore state"
```

---

## Task 3: Create NaviiAvatar component

**Files:**
- Create: `mobile/src/components/ui/NaviiAvatar.tsx`

- [ ] **Step 1: Create the component**

Create `mobile/src/components/ui/NaviiAvatar.tsx`:

```tsx
import { createAvatar } from '@usenavii/core';
import { SvgXml } from 'react-native-svg';

interface NaviiAvatarProps {
  seed: string;
  size: number;
}

export function NaviiAvatar({ seed, size }: NaviiAvatarProps) {
  const svg = createAvatar(seed, { size });
  return <SvgXml xml={svg} width={size} height={size} />;
}
```

- [ ] **Step 2: Verify TypeScript is happy**

```bash
cd taisa-os/mobile && npx tsc --noEmit 2>&1 | grep -i "NaviiAvatar" | head -10
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
cd taisa-os && git add mobile/src/components/ui/NaviiAvatar.tsx
git commit -m "feat(ui): add NaviiAvatar component"
```

---

## Task 4: Write Storybook story for NaviiAvatar

**Files:**
- Create: `mobile/src/components/ui/NaviiAvatar.stories.tsx`

- [ ] **Step 1: Create the story file**

Create `mobile/src/components/ui/NaviiAvatar.stories.tsx`:

```tsx
import type { Meta, StoryObj } from '@storybook/react-native';
import { View } from 'react-native';
import { NaviiAvatar } from './NaviiAvatar';

const meta: Meta<typeof NaviiAvatar> = {
  title: 'Components/NaviiAvatar',
  component: NaviiAvatar,
  args: {
    seed: 'baah-device-uuid',
    size: 64,
  },
  decorators: [
    (Story) => (
      <View style={{ padding: 32, alignItems: 'center', backgroundColor: '#FFFFFF' }}>
        <Story />
      </View>
    ),
  ],
};

export default meta;
type Story = StoryObj<typeof meta>;

export const Default: Story = {};

export const TabBarSize: Story = {
  name: 'Tab bar (22px)',
  args: { size: 22 },
};

export const YouScreen: Story = {
  name: 'You screen (64px)',
  args: { size: 64 },
};

export const Hero: Story = {
  name: 'Hero (88px)',
  args: { size: 88 },
};

export const DifferentSeeds: Story = {
  name: 'Different seeds → different avatars',
  render: () => (
    <View style={{ flexDirection: 'row', gap: 16, flexWrap: 'wrap', justifyContent: 'center' }}>
      <NaviiAvatar seed="seed-alpha" size={56} />
      <NaviiAvatar seed="seed-beta" size={56} />
      <NaviiAvatar seed="seed-gamma" size={56} />
      <NaviiAvatar seed="seed-delta" size={56} />
    </View>
  ),
};

export const SameSeedIsStable: Story = {
  name: 'Same seed → same avatar (rendered twice)',
  render: () => (
    <View style={{ flexDirection: 'row', gap: 16 }}>
      <NaviiAvatar seed="stable-seed" size={64} />
      <NaviiAvatar seed="stable-seed" size={64} />
    </View>
  ),
};
```

- [ ] **Step 2: Commit**

```bash
cd taisa-os && git add mobile/src/components/ui/NaviiAvatar.stories.tsx
git commit -m "test(ui): add NaviiAvatar Storybook stories"
```

---

## Task 5: Export NaviiAvatar from ui/index.ts

**Files:**
- Modify: `mobile/src/components/ui/index.ts`

- [ ] **Step 1: Add the export**

Add to the bottom of `mobile/src/components/ui/index.ts`:

```ts
export { NaviiAvatar } from './NaviiAvatar';
export type { } from './NaviiAvatar';
```

Wait — the component has no exported types beyond the component itself. Add only:

```ts
export { NaviiAvatar } from './NaviiAvatar';
```

- [ ] **Step 2: Verify TypeScript**

```bash
cd taisa-os/mobile && npx tsc --noEmit 2>&1 | head -20
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
cd taisa-os && git add mobile/src/components/ui/index.ts
git commit -m "feat(ui): export NaviiAvatar from ui index"
```

---

## Task 6: Update You screen — centered 64px avatar

**Files:**
- Modify: `mobile/app/(tabs)/you.tsx:1-82`

- [ ] **Step 1: Update imports and avatar row**

In `mobile/app/(tabs)/you.tsx`, make two changes:

**1. Add NaviiAvatar import** (add alongside existing imports):
```tsx
import { NaviiAvatar } from '../../src/components/ui/NaviiAvatar';
```

**2. Add userId to the store selector** (update line 17):
```tsx
const { profile, fetchProfile, updateProfile } = useCareerStore();
```
becomes:
```tsx
const { profile, userId, fetchProfile, updateProfile } = useCareerStore();
```

**3. Replace the avatar row** (lines 72–82). Remove:
```tsx
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
```

Replace with:
```tsx
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
```

- [ ] **Step 2: Verify TypeScript**

```bash
cd taisa-os/mobile && npx tsc --noEmit 2>&1 | grep "you.tsx" | head -10
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
cd taisa-os && git add mobile/app/(tabs)/you.tsx
git commit -m "feat(you): replace T circle with 64px centered NaviiAvatar"
```

---

## Task 7: Update TopNavBar — 22px Navii for You tab

**Files:**
- Modify: `mobile/src/components/ui/TopNavBar.tsx:1-122`

- [ ] **Step 1: Update imports**

In `mobile/src/components/ui/TopNavBar.tsx`, add two imports:

```tsx
import { NaviiAvatar } from './NaviiAvatar';
import { useCareerStore } from '../../stores/careerStore';
```

- [ ] **Step 2: Update TabButton props to accept optional userId**

Update the `TabButton` function signature (currently line 33):

```tsx
function TabButton({ tab, active, tabIndex, activeIndex, userId }: {
  tab: NavTab;
  active: boolean;
  tabIndex: number;
  activeIndex: number;
  userId: string | null;
}) {
```

- [ ] **Step 3: Replace the icon render inside TabButton**

Inside `TabButton`, the `<Pressable>` currently renders:

```tsx
        <Icon name={tab.icon} color={active ? '#060707' : '#898989'} />
```

Replace with:

```tsx
        {tab.id === 'you' && userId ? (
          <NaviiAvatar seed={userId} size={22} />
        ) : (
          <Icon name={tab.icon} color={active ? '#060707' : '#898989'} />
        )}
```

- [ ] **Step 4: Read userId in TopNavBar and pass it down**

In the `TopNavBar` function body, add after the existing hooks (after line 99 `const activeIndex = ...`):

```tsx
  const userId = useCareerStore((s) => s.userId);
```

Then update every `<TabButton>` call in the return (currently a `.map()` at line 107):

```tsx
          <TabButton key={tab.id} tab={tab} active={isActive(tab.path)} tabIndex={i} activeIndex={activeIndex} userId={userId} />
```

- [ ] **Step 5: Verify TypeScript**

```bash
cd taisa-os/mobile && npx tsc --noEmit 2>&1 | grep "TopNavBar\|TabButton" | head -10
```

Expected: no output.

- [ ] **Step 6: Commit**

```bash
cd taisa-os && git add mobile/src/components/ui/TopNavBar.tsx
git commit -m "feat(nav): replace IconPeopleCircle with 22px NaviiAvatar for You tab"
```

---

## Task 8: Final verification

- [ ] **Step 1: Full TypeScript check**

```bash
cd taisa-os/mobile && npx tsc --noEmit
```

Expected: no output (zero errors).

- [ ] **Step 2: Start the app and visually verify**

```bash
cd taisa-os && npm run mobile
```

Check:
1. You tab in the tab bar shows a small mascot avatar (not a circle icon)
2. You screen shows a 64px mascot avatar centered above the name
3. Both avatars are the same mascot
4. Navigate away and back — avatar is identical (deterministic)
5. Kill network (Airplane mode in simulator) — avatar still renders

- [ ] **Step 3: Storybook verification (optional but recommended)**

```bash
cd taisa-os/mobile && EXPO_PUBLIC_STORYBOOK=true npm run mobile
```

Navigate to `Components/NaviiAvatar`. Verify:
- Default (64px) renders a mascot
- Tab bar size (22px) renders clearly at small size
- "Different seeds" story shows 4 distinct avatars
- "Same seed is stable" story shows two identical avatars side-by-side

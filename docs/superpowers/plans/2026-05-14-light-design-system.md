# Light Design System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the dark-theme token set with the Taisa DS (based on Mande DS) light-mode system, load Strichpunkt Sans, and migrate every existing screen and component to use the new token class names.

**Architecture:** Three layers — (1) primitive palettes + semantic utilities in `tailwind.config.js`, (2) composite typography utilities in `global.css`, (3) Strichpunkt Sans loaded via `expo-font`. All "Mande DS" references in docs and code are renamed to "Taisa DS." Screen migration replaces old dark token class names with Taisa DS equivalents. The `src/constants/theme.ts` JS color values are updated to match new light tokens for components that require runtime color values (ActivityIndicator, shadows, tab bar).

**Tech Stack:** React Native / Expo, NativeWind v4, Tailwind CSS v3, expo-font v14

**Spec:** `docs/features/light-design-system.md`

---

## Token migration reference

Use this throughout all migration tasks:

| Old class | New class | Notes |
|---|---|---|
| `bg-background` | `bg-background` | Same name — value changes to `#ffffff` |
| `bg-surface` | `bg-card` | |
| `bg-surface-elevated` | `bg-muted` | |
| `text-text-primary` | `text-foreground` | |
| `text-text-secondary` | `text-muted-foreground` | |
| `text-text-tertiary` | `text-text-tertiary` | Same name — value updates |
| `text-accent` | `text-lime-700` | Readable lime on white (`#778700`) |
| `bg-accent` | `bg-primary` | Lime-500 CTA — only when used as action button |
| `bg-accent-muted` | `bg-lime-100` | Subtle lime tint |
| `border-border` | `border-border` | Same name — value changes |
| `border-border-subtle` | `border-border-subtle` | Same name |
| `text-error` | `text-danger` | |
| `text-white` | `text-inverted-foreground` | |
| Raw `#7C6FFF` | `#cdec1a` (lime-500) | Update in style props and theme.ts |
| Raw `#F0F0F8` | `#060707` (neutral-900) | Update in style props |

**JS color values** (`src/constants/theme.ts`) — use these for runtime props:
| Key | Old hex | New hex |
|---|---|---|
| `colors.accent` | `#7C6FFF` | `#cdec1a` |
| `colors.textTertiary` | `#55556A` | `#898989` |
| `colors.textPrimary` | `#F0F0F8` | `#060707` |
| `colors.surface` | `#13131A` | `#ffffff` |
| `colors.border` | `#2A2A38` | `#e6e6e6` |

---

## File map

| File | Action |
|---|---|
| `foundations.md` | Update — replace "Mande DS" → "Taisa DS" throughout |
| `mobile/tailwind.config.js` | Full rewrite — Taisa DS token set |
| `mobile/global.css` | Full rewrite — typography utilities, no Inter overrides |
| `mobile/app/_layout.tsx` | Edit — Strichpunkt Sans loading, light StatusBar, light background |
| `mobile/src/constants/theme.ts` | Edit — update all hex values to light equivalents |
| `mobile/src/components/ui/Button.tsx` | Edit — SPINNER_COLOR raw hex → theme.ts values |
| `mobile/src/components/ui/Input.tsx` | Edit — `placeholderTextColor` raw hex → theme value |
| `mobile/src/components/DigestCard.tsx` | Edit — token migration + dotColors raw hex |
| `mobile/src/components/FAB.tsx` | Edit — token migration + shadow raw hex |
| `mobile/src/components/SearchBar.tsx` | Edit — token migration + JS color import |
| `mobile/src/components/TaisaCard.tsx` | Edit — token migration |
| `mobile/src/components/TaisaReplyCard.tsx` | Edit — token migration + raw hex |
| `mobile/src/components/ThemeTag.tsx` | Edit — token migration |
| `mobile/src/components/ThreadRow.tsx` | Edit — token migration |
| `mobile/app/(tabs)/today.tsx` | Edit — token migration |
| `mobile/app/(tabs)/threads.tsx` | Edit — token migration |
| `mobile/app/(tabs)/you.tsx` | Edit — token migration + StyleSheet removal |
| `mobile/app/(tabs)/_layout.tsx` | Edit — JS color migration to new theme.ts values |
| `mobile/app/thread/[id].tsx` | Edit — token migration + raw hex |
| `mobile/app/recording/index.tsx` | Edit — token migration + raw hex |
| `mobile/app/onboarding/index.tsx` | Full rewrite — StyleSheet → NativeWind |
| `docs/design-system.md` | Full rewrite — document Taisa DS |

---

## Task 1: Rename Mande DS → Taisa DS in foundations.md

**Files:**
- Modify: `foundations.md`

- [ ] **Step 1: Replace all "Mande DS" references**

Open `foundations.md`. Replace every instance of "Mande DS" with "Taisa DS" and "Mande" with "Taisa" throughout the file.

Key lines to change:
```
# Mande DS — Foundations
```
→
```
# Taisa DS — Foundations
```

```
Designer reference for the token system. For token values, see `packages/ui/src/tokens/globals.css`.
```
→
```
Designer reference for the token system. Source of truth for all Taisa DS token decisions.
```

Remove the `packages/ui/src/tokens/globals.css` reference (it belongs to the web DS, not the mobile app).

- [ ] **Step 2: Commit**

```bash
git add foundations.md
git commit -m "docs: rename Mande DS to Taisa DS in foundations"
```

---

## Task 2: Rewrite tailwind.config.js with Taisa DS token set

**Files:**
- Modify: `mobile/tailwind.config.js`

This replaces the entire config. All OKLCH values have been pre-converted to hex.

- [ ] **Step 1: Replace tailwind.config.js**

```js
/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './app/**/*.{js,jsx,ts,tsx}',
    './src/**/*.{js,jsx,ts,tsx}',
  ],
  presets: [require('nativewind/preset')],
  theme: {
    extend: {
      // ─── Primitive palettes ────────────────────────────────────────────
      // Use palette classes directly only when no semantic utility exists.
      // Per foundations.md decision rule: semantic utility > named palette > never raw hex.
      colors: {
        neutral: {
          white: '#ffffff',
          50:  '#f9f9f9',
          100: '#f3f3f3',
          200: '#e6e6e6',
          300: '#dadada',
          400: '#898989',
          500: '#5f646a',
          600: '#44484d',
          700: '#2b2e32',
          800: '#17181b',
          900: '#060707',
        },
        lime: {
          50:  '#f6fee8',
          100: '#edfbca',
          200: '#e0f7a4',
          300: '#d8f37c',
          400: '#d3f04e',
          500: '#cdec1a',  // primary CTA
          600: '#a0b90f',
          700: '#778700',  // readable lime text on white
          800: '#4e5a00',
          900: '#2b3201',
        },
        teal: {
          50:  '#e9f9fa',
          100: '#cdf2f5',
          200: '#a4e5eb',
          300: '#6cd0d9',
          400: '#3db1bb',
          500: '#006c76',
          600: '#00565d',
          700: '#004148',
          800: '#002e33',
          900: '#001b1f',
        },
        blush: {
          50:  '#faf1f7',
          100: '#f6e3ed',
          200: '#efcadd',
          300: '#e7accd',
          400: '#e093bf',
          500: '#d973b0',
          600: '#ba4f91',
          700: '#8a386c',
          800: '#60254a',
          900: '#361228',
        },
        orange: {
          50:  '#fcf2e8',
          100: '#f9e3cc',
          200: '#f6c89a',
          300: '#f4a759',
          400: '#f58100',
          500: '#e46300',
          600: '#b54d00',
          700: '#933f00',
          800: '#703100',
          900: '#4c2200',
        },
        blue: {
          50:  '#ebf5ff',
          100: '#cde6fe',
          200: '#91c9fd',
          300: '#68b5fc',
          400: '#329afb',
          500: '#0c79e6',
          600: '#0068c6',
          700: '#04539e',
          800: '#033a6e',
          900: '#01203c',
        },
        red: {
          50:  '#fff0ea',
          100: '#ffddd2',
          200: '#ffbfae',
          300: '#ff9480',
          400: '#ff5c4c',
          500: '#c60000',
          600: '#9f0000',
          700: '#7b0000',
          800: '#5d0000',
          900: '#3d0000',
        },
        green: {
          50:  '#e7f9e9',
          100: '#d6f5da',
          200: '#adebb5',
          300: '#86e091',
          400: '#4fd062',
          500: '#04851a',
          600: '#006417',
          700: '#165022',
          800: '#18391f',
          900: '#16281a',
        },
        yellow: {
          50:  '#fffbeb',
          100: '#fef3c7',
          200: '#fde68a',
          300: '#fbd34e',
          400: '#fcbf26',
          500: '#eb9707',
          600: '#c76d04',
          700: '#9b4807',
          800: '#5d2908',
          900: '#3b1603',
        },

        // ─── Semantic utilities ────────────────────────────────────────────
        // These are the only tokens components should reference.

        // Surfaces
        background:          '#ffffff',   // page background
        foreground:          '#060707',   // primary text
        subtle:              '#f9f9f9',   // hover fill, subtle sections
        muted:               '#f3f3f3',   // input bg, disabled bg
        'muted-foreground':  '#5f646a',   // secondary text, labels
        card:                '#ffffff',   // cards, panels
        'card-foreground':   '#060707',
        popover:             '#ffffff',
        'popover-foreground':'#060707',
        overlay:             'rgba(6,7,7,0.5)',

        // Primary action (lime)
        primary:             '#cdec1a',   // CTA button bg
        'primary-hover':     '#d3f04e',   // CTA hover
        'primary-foreground':'#060707',   // text on CTA button

        // Secondary
        secondary:            '#f3f3f3',
        'secondary-foreground':'#060707',

        // Accent (neutral-subtle — hover/active fill, NOT the lime CTA)
        accent:              '#f9f9f9',   // neutral-50
        'accent-foreground': '#060707',

        // Destructive
        destructive:          '#c60000',
        'destructive-hover':  '#9f0000',
        'destructive-foreground': '#ffffff',

        // Borders
        border:              '#e6e6e6',   // default border
        'border-subtle':     'rgba(6,7,7,0.08)', // hairline
        'border-strong':     '#dadada',   // elevated border
        'border-light':      '#e6e6e6',   // alias — used by Badge outline
        input:               '#e6e6e6',
        ring:                '#5f646a',

        // Disabled
        disabled:            '#e6e6e6',
        'disabled-foreground':'#898989',

        // Inverted
        'inverted-foreground':'#ffffff',

        // Extended text token
        'text-tertiary':     '#898989',   // → class: text-text-tertiary

        // Danger
        danger:              '#c60000',
        'danger-subtle':     '#fff0ea',
        'danger-border':     '#ff9480',
        'danger-text':       '#7b0000',

        // Success
        success:             '#04851a',
        'success-subtle':    '#e7f9e9',
        'success-text':      '#006417',

        // Warning (maps to orange)
        warning:             '#e46300',
        'warning-subtle':    '#fcf2e8',
        'warning-text':      '#b54d00',

        // Info
        info:                '#0c79e6',
        'info-subtle':       '#ebf5ff',
        'info-text':         '#0068c6',

        // Orange (warm variant — used by Badge)
        'orange-subtle':     '#fcf2e8',
        'orange-text':       '#933f00',

        // Accent badge tokens (teal — used by Badge accent variant)
        'accent-bg-light':   '#e9f9fa',
        'accent-fg-light':   '#004148',
        'accent-subtle':     '#e9f9fa',
        'accent-border':     '#6cd0d9',
      },

      // ─── Typography ─────────────────────────────────────────────────────
      // Composite text utilities (text-H1, text-lg-regular, etc.) are defined
      // in global.css @layer utilities. Raw font-size utilities below are
      // Tailwind defaults — use composite utilities in new components.
      fontFamily: {
        sans:          ['StrichpunktSans'],
        'sans-medium': ['StrichpunktSans-Medium'],
        'sans-bold':   ['StrichpunktSans-Bold'],
      },

      // ─── Border radius ───────────────────────────────────────────────────
      borderRadius: {
        '1':   '4px',
        '2':   '8px',
        '3':   '12px',
        '4':   '16px',
        '5':   '20px',
        '6':   '24px',
        'full':'9999px',
        // Aliases kept for backward compat during migration
        'sm':  '8px',
        'md':  '12px',
        'lg':  '16px',
        'xl':  '24px',
        '2xl': '24px',
        '3xl': '24px',
      },

      // ─── Shadows ────────────────────────────────────────────────────────
      boxShadow: {
        '2xs': '0 1px 0 0 rgba(0, 0, 0, 0.05)',
        'xs':  '0 1px 2px 0 rgba(23, 23, 23, 0.04)',
        'sm':  '0 1px 4px 0 rgba(23, 23, 23, 0.04)',
        'md':  '0 4px 6px -1px rgba(23, 23, 23, 0.08)',
        'lg':  '0 10px 15px -3px rgba(23, 23, 23, 0.08)',
        'xl':  '0 20px 25px -5px rgba(23, 23, 23, 0.08)',
      },
    },
  },
  plugins: [],
};
```

- [ ] **Step 2: Verify NativeWind can parse the config**

```bash
cd mobile && npx tailwindcss --content './app/**/*.tsx' --input ./global.css --dry-run 2>&1 | head -20
```

Expected: no errors. If you see "cannot resolve" errors, check the `presets` line is present.

- [ ] **Step 3: Commit**

```bash
git add mobile/tailwind.config.js
git commit -m "feat: add Taisa DS token set to tailwind.config.js"
```

---

## Task 3: Rewrite global.css — typography utilities

**Files:**
- Modify: `mobile/global.css`

NativeWind v4 compiles `@layer utilities` classes to React Native styles. CSS variables and `var()` do NOT resolve in React Native — all values must be inlined. No `font-family` here — that's set via `expo-font` in `_layout.tsx`.

- [ ] **Step 1: Replace global.css**

```css
@tailwind base;
@tailwind components;
@tailwind utilities;

/* ============================================================
   TAISA DS — TYPOGRAPHY UTILITIES
   Inlined values (no CSS variables — React Native doesn't resolve them).
   Mobile sizes only — no responsive breakpoints in RN.
   ============================================================ */

@layer utilities {
  /* Headings */
  .text-H1 {
    font-size: 20px;
    line-height: 36px;
    font-weight: 600;
    letter-spacing: -0.4px;
  }
  .text-H2 {
    font-size: 18px;
    line-height: 32px;
    font-weight: 600;
    letter-spacing: -0.36px;
  }
  .text-H3 {
    font-size: 18px;
    line-height: 28px;
    font-weight: 600;
    letter-spacing: -0.36px;
  }

  /* XLarge body */
  .text-xlg-regular  { font-size: 18px; line-height: 26px; font-weight: 400; letter-spacing: -0.36px; }
  .text-xlg-medium   { font-size: 18px; line-height: 26px; font-weight: 500; letter-spacing: -0.36px; }
  .text-xlg-semibold { font-size: 18px; line-height: 26px; font-weight: 600; letter-spacing: -0.36px; }

  /* Large body */
  .text-lg-regular  { font-size: 16px; line-height: 24px; font-weight: 400; letter-spacing: -0.12px; }
  .text-lg-medium   { font-size: 16px; line-height: 24px; font-weight: 500; letter-spacing: -0.12px; }
  .text-lg-semibold { font-size: 16px; line-height: 24px; font-weight: 600; letter-spacing: -0.12px; }

  /* Base UI */
  .text-base-regular  { font-size: 14px; line-height: 20px; font-weight: 400; letter-spacing: 0.02px; }
  .text-base-medium   { font-size: 14px; line-height: 20px; font-weight: 500; letter-spacing: 0.02px; }
  .text-base-semibold { font-size: 14px; line-height: 20px; font-weight: 600; letter-spacing: 0.02px; }

  /* Small / captions */
  .text-small-regular  { font-size: 12px; line-height: 18px; font-weight: 400; letter-spacing: 0; }
  .text-small-medium   { font-size: 12px; line-height: 18px; font-weight: 500; letter-spacing: 0; }
  .text-small-semibold { font-size: 12px; line-height: 18px; font-weight: 600; letter-spacing: 0; }
}
```

- [ ] **Step 2: Commit**

```bash
git add mobile/global.css
git commit -m "feat: add Taisa DS typography utilities to global.css"
```

---

## Task 4: Load Strichpunkt Sans + update _layout.tsx

**Files:**
- Create: `mobile/assets/fonts/` (font files — manual download)
- Modify: `mobile/app/_layout.tsx`

- [ ] **Step 1: Download Strichpunkt Sans from Google Fonts**

1. Go to Google Fonts and download Strichpunkt Sans
2. Place the font files in `mobile/assets/fonts/`:
   - `StrichpunktSans-Regular.ttf`
   - `StrichpunktSans-Medium.ttf`
   - `StrichpunktSans-Bold.ttf`

- [ ] **Step 2: Update _layout.tsx**

```tsx
import '../global.css';
import { useEffect } from 'react';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useFonts } from 'expo-font';
import * as SplashScreen from 'expo-splash-screen';
import * as SecureStore from 'expo-secure-store';
import { useCareerStore } from '../src/stores/careerStore';

SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  const { fetchProfile } = useCareerStore();

  const [fontsLoaded] = useFonts({
    'StrichpunktSans': require('../assets/fonts/StrichpunktSans-Regular.ttf'),
    'StrichpunktSans-Medium': require('../assets/fonts/StrichpunktSans-Medium.ttf'),
    'StrichpunktSans-Bold': require('../assets/fonts/StrichpunktSans-Bold.ttf'),
  });

  useEffect(() => {
    if (fontsLoaded) {
      SplashScreen.hideAsync();
    }
  }, [fontsLoaded]);

  useEffect(() => {
    async function hydrateUser() {
      const userId = await SecureStore.getItemAsync('userId');
      if (userId) {
        try {
          await fetchProfile();
        } catch (e) {
          // Profile fetch failed — user will see onboarding
        }
      }
    }
    hydrateUser();
  }, []);

  if (!fontsLoaded) return null;

  return (
    <>
      <StatusBar style="dark" />
      <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: '#ffffff' } }}>
        <Stack.Screen name="(tabs)" />
        <Stack.Screen name="onboarding/index" />
        <Stack.Screen name="thread/[id]" />
        <Stack.Screen
          name="recording/index"
          options={{ presentation: 'transparentModal', animation: 'slide_from_bottom' }}
        />
      </Stack>
    </>
  );
}
```

Key changes:
- `StatusBar style="light"` → `style="dark"` (light background needs dark status bar icons)
- `backgroundColor: '#0A0A0F'` → `'#ffffff'`
- Font loading with `useFonts` and splash screen hold

- [ ] **Step 3: Check if expo-splash-screen is installed**

```bash
cd mobile && grep "expo-splash-screen" package.json
```

If not listed, install it:
```bash
cd mobile && npm install expo-splash-screen
```

- [ ] **Step 4: Commit**

```bash
git add mobile/app/_layout.tsx mobile/assets/fonts/
git commit -m "feat: load Strichpunkt Sans and switch to light status bar"
```

---

## Task 5: Update theme.ts — sync JS color values

**Files:**
- Modify: `mobile/src/constants/theme.ts`

Several components use `colors.*` for runtime props (ActivityIndicator `color`, shadow `shadowColor`, tab bar). These need to match the new light token values.

- [ ] **Step 1: Update the colors object**

Replace the `colors` export with:

```ts
export const colors = {
  background: '#ffffff',
  surface: '#ffffff',
  surfaceElevated: '#f9f9f9',
  border: '#e6e6e6',
  borderSubtle: 'rgba(6,7,7,0.08)',

  // Primary (lime-500)
  accent: '#cdec1a',
  accentMuted: '#edfbca',
  accentGlow: 'rgba(205,236,26,0.3)',

  // Semantic
  positive: '#04851a',
  positiveMuted: '#e7f9e9',
  warning: '#e46300',
  warningMuted: '#fcf2e8',
  error: '#c60000',
  errorMuted: '#fff0ea',
  info: '#0c79e6',

  // Text
  textPrimary: '#060707',
  textSecondary: '#5f646a',
  textTertiary: '#898989',
  textAccent: '#778700',

  // Momentum signals
  momentum: {
    accelerating: '#04851a',
    steady: '#0c79e6',
    stalling: '#e46300',
    recovering: '#004148',
  },

  // Sentiment
  sentiment: {
    'very-positive': '#04851a',
    positive: '#86e091',
    neutral: '#0c79e6',
    challenging: '#e46300',
    difficult: '#c60000',
  },

  // Spacing kept for any legacy usage
  spacing: { xs: 4, sm: 8, md: 16, lg: 24, xl: 32, xxl: 48 },
  radius: { sm: 8, md: 12, lg: 16, xl: 24, full: 9999 },
  fontSize: { xs: 11, sm: 13, base: 15, md: 17, lg: 20, xl: 24 },
};
```

- [ ] **Step 2: Commit**

```bash
git add mobile/src/constants/theme.ts
git commit -m "feat: update theme.ts color values to Taisa DS light tokens"
```

---

## Task 6: Migrate DS components — Button and Input

**Files:**
- Modify: `mobile/src/components/ui/Button.tsx`
- Modify: `mobile/src/components/ui/Input.tsx`

Badge and Card already use Mande DS token names correctly. Only Button (raw hex spinner colors) and Input (raw hex placeholder color) need changes.

- [ ] **Step 1: Update Button.tsx SPINNER_COLOR and text sizes**

In `Button.tsx`, find the `SPINNER_COLOR` constant and replace raw hex with theme-derived values:

```tsx
import { colors } from '../../constants/theme';

// Replace the static SPINNER_COLOR constant with:
const SPINNER_COLOR: Record<ButtonVariant, string> = {
  'primary':               colors.textPrimary,        // dark text — lime bg is light
  'secondary':             colors.textPrimary,
  'tertiary':              colors.textPrimary,
  'destructive':           '#ffffff',
  'secondary-destructive': colors.error,
  'tertiary-destructive':  colors.error,
};
```

Also update the disabled spinner:
```tsx
// Find: color={isDisabled ? '#A3A3A3' : SPINNER_COLOR[variant]}
// Replace:
color={isDisabled ? colors.textTertiary : SPINNER_COLOR[variant]}
```

- [ ] **Step 2: Update Input.tsx placeholder color**

In `Input.tsx`, find `placeholderTextColor="#737373"` and replace:

```tsx
import { colors } from '../../constants/theme';

// Replace:
placeholderTextColor={colors.textTertiary}
```

- [ ] **Step 3: Commit**

```bash
git add mobile/src/components/ui/Button.tsx mobile/src/components/ui/Input.tsx
git commit -m "feat: update Button and Input raw hex colors to theme.ts values"
```

---

## Task 7: Migrate screen components

**Files:**
- Modify: `mobile/src/components/DigestCard.tsx`
- Modify: `mobile/src/components/FAB.tsx`
- Modify: `mobile/src/components/SearchBar.tsx`
- Modify: `mobile/src/components/TaisaCard.tsx`
- Modify: `mobile/src/components/TaisaReplyCard.tsx`
- Modify: `mobile/src/components/ThemeTag.tsx`
- Modify: `mobile/src/components/ThreadRow.tsx`

- [ ] **Step 1: Replace DigestCard.tsx**

```tsx
import { View, Text, TouchableOpacity } from 'react-native';
import { router } from 'expo-router';

interface DigestItem {
  type: string;
  color: string;
  text: string;
  cta: string;
}

interface DigestCardProps {
  headline: string;
  items: DigestItem[];
}

const dotColors: Record<string, string> = {
  accent:   '#cdec1a',  // lime-500
  positive: '#04851a',  // green-500
  warning:  '#e46300',  // orange-500
};

export function DigestCard({ headline, items }: DigestCardProps) {
  return (
    <View className="bg-card rounded-xl px-4 py-4 mb-4 border border-border">
      <Text className="text-lime-700 text-xs font-bold uppercase tracking-wider mb-1">Taisa's week in review</Text>
      <Text className="text-foreground text-base font-bold mb-1">{headline}</Text>
      <Text className="text-text-tertiary text-xs mb-4">Tap any item to continue</Text>

      {items.map((item, i) => (
        <TouchableOpacity
          key={i}
          onPress={() => router.push('/recording')}
          className="flex-row items-start mb-3"
        >
          <View
            className="w-2 h-2 rounded-full mt-1 mr-3 flex-shrink-0"
            style={{ backgroundColor: dotColors[item.color] ?? '#cdec1a' }}
          />
          <View className="flex-1">
            <Text className="text-muted-foreground text-sm leading-relaxed">{item.text}</Text>
            <Text className="text-lime-700 text-xs mt-0.5">{item.cta}</Text>
          </View>
        </TouchableOpacity>
      ))}
    </View>
  );
}
```

- [ ] **Step 2: Replace FAB.tsx**

```tsx
import { TouchableOpacity, Text, View } from 'react-native';
import { router } from 'expo-router';

interface FABProps {
  onPress?: () => void;
}

export function FAB({ onPress }: FABProps) {
  const handlePress = onPress ?? (() => router.push('/recording'));

  return (
    <View className="absolute bottom-6 right-6" style={{ zIndex: 50 }}>
      <TouchableOpacity
        onPress={handlePress}
        className="w-14 h-14 rounded-full bg-primary items-center justify-center"
        style={{
          elevation: 8,
          shadowColor: '#cdec1a',
          shadowOffset: { width: 0, height: 4 },
          shadowOpacity: 0.4,
          shadowRadius: 8,
        }}
      >
        <Text className="text-foreground text-2xl font-light">+</Text>
      </TouchableOpacity>
    </View>
  );
}
```

- [ ] **Step 3: Replace SearchBar.tsx**

```tsx
import { View, TextInput, Text } from 'react-native';
import { colors } from '../constants/theme';

interface SearchBarProps {
  value: string;
  onChangeText: (text: string) => void;
  placeholder?: string;
}

export function SearchBar({ value, onChangeText, placeholder = 'Search conversations...' }: SearchBarProps) {
  return (
    <View className="bg-muted rounded-full px-4 py-2 mb-3 flex-row items-center border border-border">
      <Text className="text-text-tertiary text-base mr-2">⌕</Text>
      <TextInput
        value={value}
        onChangeText={onChangeText}
        placeholder={placeholder}
        placeholderTextColor={colors.textTertiary}
        className="flex-1 text-foreground text-sm"
        autoCapitalize="none"
        autoCorrect={false}
      />
    </View>
  );
}
```

- [ ] **Step 4: Replace TaisaCard.tsx**

```tsx
import { View, Text, TouchableOpacity } from 'react-native';
import { router } from 'expo-router';

interface TaisaCardProps {
  eyebrow: string;
  body: string;
  cta: string;
  onPress?: () => void;
}

export function TaisaCard({ eyebrow, body, cta, onPress }: TaisaCardProps) {
  const handlePress = onPress ?? (() => router.push('/recording'));

  return (
    <TouchableOpacity
      onPress={handlePress}
      className="bg-card rounded-xl px-4 py-4 mb-4 border border-border"
      style={{ borderLeftWidth: 2, borderLeftColor: '#cdec1a' }}
    >
      <Text className="text-lime-700 text-xs font-bold uppercase tracking-wider mb-2">{eyebrow}</Text>
      <Text className="text-foreground text-sm leading-relaxed mb-3">{body}</Text>
      <Text className="text-lime-700 text-xs font-semibold">{cta}</Text>
    </TouchableOpacity>
  );
}
```

- [ ] **Step 5: Replace TaisaReplyCard.tsx**

```tsx
import { View, Text } from 'react-native';

interface TaisaReplyCardProps {
  content: string;
}

export function TaisaReplyCard({ content }: TaisaReplyCardProps) {
  return (
    <View
      className="bg-card rounded-lg rounded-tl-sm px-3 py-3 my-1 border border-border"
      style={{ borderLeftWidth: 2, borderLeftColor: '#cdec1a' }}
    >
      <Text className="text-lime-700 text-xs font-bold mb-1">Taisa</Text>
      <Text className="text-muted-foreground text-sm leading-relaxed">{content}</Text>
    </View>
  );
}
```

- [ ] **Step 6: Replace ThemeTag.tsx**

```tsx
import { View, Text } from 'react-native';

interface ThemeTagProps {
  label: string;
}

export function ThemeTag({ label }: ThemeTagProps) {
  return (
    <View className="bg-lime-100 rounded-md px-2 py-0.5 mr-1 mb-1">
      <Text className="text-lime-700 text-xs font-semibold">{label}</Text>
    </View>
  );
}
```

- [ ] **Step 7: Replace ThreadRow.tsx**

```tsx
import { TouchableOpacity, View, Text } from 'react-native';
import { router } from 'expo-router';
import { formatDistanceToNow } from 'date-fns';
import type { Thread } from '../stores/threadStore';

interface ThreadRowProps {
  thread: Thread;
}

export function ThreadRow({ thread }: ThreadRowProps) {
  const relativeTime = formatDistanceToNow(new Date(thread.lastMessageAt), { addSuffix: false });
  const displayTime = thread.isLive ? 'Today' : relativeTime;

  return (
    <TouchableOpacity
      onPress={() => router.push(`/thread/${thread.id}`)}
      className="bg-card rounded-xl px-3 py-3 mb-2 border border-border"
    >
      {thread.isLive && (
        <View className="flex-row items-center gap-1 mb-1">
          <View className="w-1.5 h-1.5 rounded-full bg-primary" />
          <Text className="text-lime-700 text-xs font-bold tracking-wider uppercase">Live</Text>
        </View>
      )}

      <View className="flex-row justify-between items-center mb-1">
        <Text className="text-foreground text-sm font-semibold flex-1 mr-2" numberOfLines={1}>
          {thread.title}
        </Text>
        <Text className="text-text-tertiary text-xs">{displayTime}</Text>
      </View>

      {thread.isVoice && thread.lastUserMessage == null ? (
        <Text className="text-muted-foreground text-xs mb-1">〜〜〜  {formatDuration(thread.audioDurationSeconds ?? 0)} voice</Text>
      ) : (
        <Text className="text-muted-foreground text-xs mb-1" numberOfLines={1}>
          {thread.lastUserMessage ?? ''}
        </Text>
      )}

      {thread.lastAssistantMessage != null && (
        <Text className="text-lime-700 text-xs" numberOfLines={2}>
          {thread.lastAssistantMessage}
        </Text>
      )}
    </TouchableOpacity>
  );
}

function formatDuration(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.round(seconds % 60).toString().padStart(2, '0');
  return `${m}:${s}`;
}
```

- [ ] **Step 8: Commit**

```bash
git add mobile/src/components/
git commit -m "feat: migrate screen components to Taisa DS light tokens"
```

---

## Task 8: Migrate app screens — Today, Threads, Thread detail

**Files:**
- Modify: `mobile/app/(tabs)/today.tsx`
- Modify: `mobile/app/(tabs)/threads.tsx`
- Modify: `mobile/app/thread/[id].tsx`

- [ ] **Step 1: Update today.tsx**

Replace all old token class names using the migration reference at the top of this plan:

```tsx
import { useCallback, useState } from 'react';
import { View, Text, ScrollView, ActivityIndicator } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { format } from 'date-fns';
import { useThreadStore } from '../../src/stores/threadStore';
import { ThreadRow } from '../../src/components/ThreadRow';
import { TaisaCard } from '../../src/components/TaisaCard';
import { DigestCard } from '../../src/components/DigestCard';
import { FAB } from '../../src/components/FAB';
import { colors } from '../../src/constants/theme';
import api from '../../src/services/api';

interface TodayCardData {
  type: string;
  eyebrow: string;
  body: string;
  cta: string;
}

interface DigestData {
  headline: string;
  items: Array<{ type: string; color: string; text: string; cta: string }>;
}

export default function TodayScreen() {
  const { threads, isLoadingThreads, fetchThreads } = useThreadStore();
  const [card, setCard] = useState<TodayCardData | null>(null);
  const [digest, setDigest] = useState<DigestData | null>(null);
  const [showDigest, setShowDigest] = useState(false);
  const [isLoadingToday, setIsLoadingToday] = useState(true);

  useFocusEffect(
    useCallback(() => {
      fetchThreads();
      loadTodayData();
    }, [])
  );

  const loadTodayData = async () => {
    setIsLoadingToday(true);
    try {
      const [cardRes, digestRes] = await Promise.all([
        api.get('/today/card'),
        api.get('/today/digest'),
      ]);
      setCard(cardRes.data.data.card);
      setShowDigest(digestRes.data.data.showDigest);
      setDigest(digestRes.data.data.digest ?? null);
    } catch (e) {
      // Silent fail
    } finally {
      setIsLoadingToday(false);
    }
  };

  const today = new Date();
  const recentThreads = threads.slice(0, 3);

  return (
    <View className="flex-1 bg-background">
      <ScrollView
        className="flex-1"
        contentContainerStyle={{ paddingHorizontal: 16, paddingTop: 60, paddingBottom: 100 }}
      >
        <Text className="text-foreground text-2xl font-bold">Today</Text>
        <Text className="text-text-tertiary text-xs mt-1 mb-5">{format(today, 'EEEE, d MMMM')}</Text>

        {isLoadingToday ? (
          <View className="bg-card rounded-xl px-4 py-4 mb-4 opacity-40 border border-border">
            <View className="h-2 bg-muted rounded mb-3 w-1/3" />
            <View className="h-3 bg-muted rounded mb-2 w-full" />
            <View className="h-3 bg-muted rounded w-3/4" />
          </View>
        ) : showDigest && digest ? (
          <DigestCard headline={digest.headline} items={digest.items} />
        ) : card ? (
          <TaisaCard eyebrow={card.eyebrow} body={card.body} cta={card.cta} />
        ) : null}

        {recentThreads.length > 0 && (
          <>
            <Text className="text-text-tertiary text-xs font-bold uppercase tracking-wider mb-3">
              {showDigest ? 'Last week' : 'Recent'}
            </Text>
            {isLoadingThreads && recentThreads.length === 0 ? (
              <ActivityIndicator color={colors.accent} />
            ) : (
              recentThreads.map(thread => <ThreadRow key={thread.id} thread={thread} />)
            )}
          </>
        )}
      </ScrollView>

      <FAB />
    </View>
  );
}
```

- [ ] **Step 2: Update threads.tsx**

```tsx
import { useCallback, useState } from 'react';
import { View, Text, ScrollView, ActivityIndicator } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { useThreadStore } from '../../src/stores/threadStore';
import { ThreadRow } from '../../src/components/ThreadRow';
import { SearchBar } from '../../src/components/SearchBar';
import { FAB } from '../../src/components/FAB';
import { colors } from '../../src/constants/theme';

export default function ThreadsScreen() {
  const { threads, isLoadingThreads, fetchThreads } = useThreadStore();
  const [query, setQuery] = useState('');

  useFocusEffect(
    useCallback(() => {
      fetchThreads();
    }, [])
  );

  const filtered = query.trim()
    ? threads.filter(t =>
        t.title.toLowerCase().includes(query.toLowerCase()) ||
        (t.lastUserMessage ?? '').toLowerCase().includes(query.toLowerCase()) ||
        (t.lastAssistantMessage ?? '').toLowerCase().includes(query.toLowerCase())
      )
    : threads;

  return (
    <View className="flex-1 bg-background">
      <ScrollView className="flex-1" contentContainerStyle={{ paddingHorizontal: 16, paddingTop: 60, paddingBottom: 100 }}>
        <Text className="text-foreground text-2xl font-bold mb-4">Threads</Text>

        <SearchBar value={query} onChangeText={setQuery} />

        {isLoadingThreads && threads.length === 0 ? (
          <ActivityIndicator color={colors.accent} style={{ marginTop: 40 }} />
        ) : filtered.length === 0 ? (
          <Text className="text-text-tertiary text-sm text-center mt-10">
            {query ? 'No threads match your search.' : 'No threads yet — tap + to start recording.'}
          </Text>
        ) : (
          filtered.map(thread => <ThreadRow key={thread.id} thread={thread} />)
        )}
      </ScrollView>

      <FAB />
    </View>
  );
}
```

- [ ] **Step 3: Update thread/[id].tsx**

Replace all token class names throughout the file:

Key replacements:
- `bg-background` → `bg-background`
- `text-accent` → `text-lime-700`
- `border-border-subtle` → `border-border-subtle`
- `text-text-primary` → `text-foreground`
- `text-text-secondary` → `text-muted-foreground`
- `text-text-tertiary` → `text-text-tertiary`
- `bg-surface` → `bg-card`
- `bg-surface-elevated` → `bg-muted`
- `bg-accent-muted` (user chat bubble) → `bg-lime-100`
- `borderLeftColor: '#7C6FFF'` → `'#cdec1a'`
- `text-white` → `text-foreground` (on lime bg, text should be dark)
- `bg-accent` (send button) → `bg-primary`
- `placeholderTextColor={colors.textTertiary}` — keep as-is (theme.ts updated in Task 5)
- `color={colors.accent}` for ActivityIndicator — keep as-is (theme.ts updated in Task 5)

Full updated thread/[id].tsx — apply all substitutions to the existing file. The structure stays identical; only class names and hex values change.

- [ ] **Step 4: Commit**

```bash
git add mobile/app/(tabs)/today.tsx mobile/app/(tabs)/threads.tsx mobile/app/thread/
git commit -m "feat: migrate Today, Threads, and Thread screens to Taisa DS tokens"
```

---

## Task 9: Migrate app screens — You tab, tab layout, Recording

**Files:**
- Modify: `mobile/app/(tabs)/you.tsx`
- Modify: `mobile/app/(tabs)/_layout.tsx`
- Modify: `mobile/app/recording/index.tsx`

- [ ] **Step 1: Update you.tsx**

Key replacements throughout the file:
- `bg-surface` → `bg-card`
- `text-accent` → `text-lime-700`
- `text-text-primary` → `text-foreground`
- `text-text-secondary` → `text-muted-foreground`
- `text-text-tertiary` → `text-text-tertiary`
- `bg-background` → `bg-background`
- `bg-border` (handle bar div) → `bg-border`
- `bg-accent` (Save button) → `bg-primary`
- `text-white` (Save button label) → `text-foreground` (lime bg is light — dark text)
- Modal backdrop `rgba(0,0,0,0.5)` → `rgba(6,7,7,0.5)`
- `placeholderTextColor={colors.textTertiary}` — keep as-is (theme.ts updated)

- [ ] **Step 2: Update _layout.tsx (tabs)**

```tsx
import { Tabs } from 'expo-router';
import { Text } from 'react-native';

export default function TabLayout() {
  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarStyle: {
          backgroundColor: '#ffffff',
          borderTopColor: '#e6e6e6',
          borderTopWidth: 1,
          paddingTop: 8,
          height: 80,
        },
        tabBarActiveTintColor: '#cdec1a',
        tabBarInactiveTintColor: '#898989',
        tabBarShowLabel: true,
        tabBarLabelStyle: { fontSize: 10, fontWeight: '500', marginBottom: 4 },
      }}
    >
      <Tabs.Screen
        name="today"
        options={{
          title: 'Today',
          tabBarIcon: ({ color }) => (
            <TabIcon symbol="◈" color={color} />
          ),
        }}
      />
      <Tabs.Screen
        name="threads"
        options={{
          title: 'Threads',
          tabBarIcon: ({ color }) => (
            <TabIcon symbol="◎" color={color} />
          ),
        }}
      />
      <Tabs.Screen
        name="you"
        options={{
          title: 'You',
          tabBarIcon: ({ color }) => (
            <TabIcon symbol="○" color={color} />
          ),
        }}
      />
    </Tabs>
  );
}

function TabIcon({ symbol, color }: { symbol: string; color: string }) {
  return (
    <Text style={{ color, fontSize: 18, lineHeight: 22 }}>{symbol}</Text>
  );
}
```

Key changes: removed `colors` import, inlined the new token values directly.

- [ ] **Step 3: Update recording/index.tsx**

Key replacements:
- `bg-background` → `bg-background`
- `bg-border` (handle) → `bg-border`
- `text-error` → `text-danger`
- `bg-surface` → `bg-muted` or `bg-card`
- `text-text-primary` → `text-foreground`
- `text-text-secondary` → `text-muted-foreground`
- `text-text-tertiary` → `text-text-tertiary`
- `text-accent` → `text-lime-700`
- `bg-accent` (record button) → `bg-primary`
- `shadowColor: '#7C6FFF'` → `'#cdec1a'`
- `color={colors.accent}` (ActivityIndicator) — keep as-is (theme.ts updated)

Apply all substitutions to the existing file.

- [ ] **Step 4: Commit**

```bash
git add mobile/app/(tabs)/you.tsx mobile/app/(tabs)/_layout.tsx mobile/app/recording/
git commit -m "feat: migrate You, tab layout, and Recording screens to Taisa DS tokens"
```

---

## Task 10: Migrate onboarding — StyleSheet → NativeWind

**Files:**
- Modify: `mobile/app/onboarding/index.tsx`

This is the only screen still using `StyleSheet.create()`. Full NativeWind conversion required.

- [ ] **Step 1: Read the full current file**

```bash
cat mobile/app/onboarding/index.tsx
```

- [ ] **Step 2: Rewrite without StyleSheet**

Remove `StyleSheet` import. Replace all `style={styles.xxx}` with NativeWind class names using the Taisa DS token map. Key mapping for onboarding:

- Container/background: `bg-background`
- Cards / selection panels: `bg-card border border-border rounded-3`
- Selected state: `bg-lime-100 border-2 border-primary`
- Headings: `text-foreground text-H2`
- Body: `text-muted-foreground text-lg-regular`
- Labels/tags: `text-text-tertiary text-small-semibold`
- Primary button: `bg-primary rounded-full py-3 px-6`
- Button text: `text-foreground text-base-semibold` (dark text on lime bg)
- Input fields: use the `Input` DS component from `../../src/components/ui/Input`
- Remove `colors` import from `../../src/constants/theme`

After rewriting, verify there are no remaining `StyleSheet.create()` calls:
```bash
grep -n "StyleSheet" mobile/app/onboarding/index.tsx
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add mobile/app/onboarding/index.tsx
git commit -m "feat: migrate onboarding to NativeWind + Taisa DS tokens"
```

---

## Task 11: Update docs/design-system.md

**Files:**
- Modify: `docs/design-system.md`

- [ ] **Step 1: Rewrite the doc**

Replace the entire file content with:

```markdown
# Taisa Design System

Living reference for all UI work. Update when a new component is added or a token changes.
Full token definitions and decision rules: `foundations.md` (root of repo).

---

## Status

| Layer | State |
|---|---|
| Styling | NativeWind (Tailwind CSS for React Native) — all screens |
| Tokens | Taisa DS light theme — `mobile/tailwind.config.js` + `mobile/global.css` |
| Typography | Strichpunkt Sans — loaded via `expo-font` in `app/_layout.tsx` |
| Components | Primitives in `mobile/src/components/ui/` |

---

## How to use tokens

**Always use the semantic utility layer — never raw hex, never palette classes unless no semantic exists.**

```
1. Semantic utility first  — bg-background, text-foreground, bg-primary
2. Named palette fallback  — bg-lime-100 (only when no semantic alias covers the role)
3. Never                   — raw hex values
```

---

## Color tokens

### Semantic utilities (use these)

| Token | Class | Hex | Role |
|---|---|---|---|
| Page background | `bg-background` | `#ffffff` | Root screen background |
| Card surface | `bg-card` | `#ffffff` | Cards, panels, modals |
| Subtle fill | `bg-subtle` | `#f9f9f9` | Hover states, subtle sections |
| Muted fill | `bg-muted` | `#f3f3f3` | Input backgrounds, disabled |
| Primary text | `text-foreground` | `#060707` | Headings, body copy |
| Secondary text | `text-muted-foreground` | `#5f646a` | Labels, metadata |
| Tertiary text | `text-text-tertiary` | `#898989` | Placeholders, timestamps |
| Default border | `border-border` | `#e6e6e6` | Cards, inputs |
| Subtle border | `border-border-subtle` | `rgba(6,7,7,0.08)` | Hairline separators |
| Strong border | `border-border-strong` | `#dadada` | Elevated borders |
| Primary CTA bg | `bg-primary` | `#cdec1a` | Buttons, FAB, active indicators |
| Primary hover | `bg-primary-hover` | (active: state) | CTA hover/press |
| Text on primary | `text-primary-foreground` | `#060707` | Text on lime buttons |
| Lime accent text | `text-lime-700` | `#778700` | Accent-colored text on light bg |
| Lime subtle bg | `bg-lime-100` | `#edfbca` | ThemeTag, subtle tints |

### Status utilities

| Status | Text/icon | Subtle bg |
|---|---|---|
| Success | `text-success` (`#04851a`) | `bg-success-subtle` (`#e7f9e9`) |
| Warning | `text-warning` (`#e46300`) | `bg-warning-subtle` (`#fcf2e8`) |
| Danger | `text-danger` (`#c60000`) | `bg-danger-subtle` (`#fff0ea`) |
| Info | `text-info` (`#0c79e6`) | `bg-info-subtle` (`#ebf5ff`) |

---

## Typography

Never use raw `text-sm font-semibold` combinations — use the composite utilities:

| Class | Size | Weight | Use for |
|---|---|---|---|
| `text-H1` | 20px / 36px lh | 600 | Page headings |
| `text-H2` | 18px / 32px lh | 600 | Section headings |
| `text-H3` | 18px / 28px lh | 600 | Sub-headings |
| `text-xlg-regular` | 18px / 26px lh | 400 | Large body |
| `text-lg-regular` | 16px / 24px lh | 400 | Default body |
| `text-lg-medium` | 16px / 24px lh | 500 | Body emphasis |
| `text-lg-semibold` | 16px / 24px lh | 600 | Body strong |
| `text-base-regular` | 14px / 20px lh | 400 | UI labels |
| `text-base-medium` | 14px / 20px lh | 500 | UI emphasis |
| `text-base-semibold` | 14px / 20px lh | 600 | UI strong |
| `text-small-regular` | 12px / 18px lh | 400 | Captions, meta |
| `text-small-medium` | 12px / 18px lh | 500 | Caption emphasis |
| `text-small-semibold` | 12px / 18px lh | 600 | Caption strong |

---

## Border radius

| Class | Value | Use for |
|---|---|---|
| `rounded-1` | 4px | Badges, chips |
| `rounded-2` | 8px | Inputs, small buttons |
| `rounded-3` | 12px | Cards, modals |
| `rounded-4` | 16px | Larger panels, sheets |
| `rounded-full` | 9999px | Pills, FAB, avatars |

---

## Components (`mobile/src/components/ui/`)

| Component | Props | Notes |
|---|---|---|
| `Button` | `variant`, `size`, `label`, `icon`, `loading`, `disabled` | Six variants; three sizes |
| `Badge` | `color`, `appearance`, `size`, `icon`, `onDismiss` | Eight colors; three appearances |
| `Card` | `surface`, `className`, `style` | Two surfaces (default / elevated) |
| `Input` | `size`, `error`, `...TextInputProps` | Two sizes; error state |

**Extraction rule:** pattern appears in 2+ places → extract to `ui/`. Do not extract speculatively.
**DS compliance:** no `StyleSheet.create()`, no raw hex, import tokens from Tailwind classes only.
```

- [ ] **Step 2: Commit**

```bash
git add docs/design-system.md
git commit -m "docs: rewrite design-system.md for Taisa DS light theme"
```

---

## Task 12: Verify in simulator

- [ ] **Step 1: Start the backend**

```bash
# From repo root
npm run backend
```

Expected: `Server running on port 3000` (or similar).

- [ ] **Step 2: Start the mobile app**

```bash
# From repo root
npm run mobile
```

- [ ] **Step 3: Open in iOS Simulator**

Press `i` in the Expo CLI to open in the iOS Simulator.

- [ ] **Step 4: Visual verification checklist**

Check each screen systematically:

- [ ] Splash screen shows without crash
- [ ] Onboarding: white background, dark text, lime selection state, Strichpunkt Sans font visible
- [ ] Today tab: white background, dark text, cards with visible borders, lime FAB
- [ ] Threads tab: white background, thread rows visible with dark text
- [ ] You tab: white background, lime Save button (with dark text on it)
- [ ] Thread detail: white background, lime "Taisa" label, lime send button
- [ ] Recording sheet: white background, lime record button, dark text
- [ ] Tab bar: white background, lime active tab indicator, grey inactive tabs
- [ ] No white-on-white invisible text anywhere
- [ ] No token resolution failures (pink/red error overlays from NativeWind)

- [ ] **Step 5: Fix any visual issues found**

Common issues to watch for:
- Font not loading: check `assets/fonts/` filenames match exactly what `useFonts` expects
- Token not resolving (shows as undefined/transparent): check the token name in `tailwind.config.js`
- Text invisible on lime button: `text-foreground` not `text-white` or `text-inverted-foreground`

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "feat: complete Taisa DS light theme migration"
```

---

## Self-review

**Spec coverage:**
- [x] `tailwind.config.js` — full Mande DS light token set → Task 2
- [x] Dark-only tokens removed → Task 2 (full rewrite)
- [x] Typography utilities (`text-H1` etc.) → Task 3
- [x] Strichpunkt Sans, Inter overrides removed → Tasks 3 + 4
- [x] Radius tokens (`rounded-1` through `rounded-4`) → Task 2
- [x] All screens migrated → Tasks 8, 9, 10
- [x] All DS components migrated → Tasks 6, 7
- [x] No `StyleSheet.create()` → Task 10 (onboarding), Tasks 6-9 (verified existing)
- [x] `docs/design-system.md` updated → Task 11
- [x] "Mande" references renamed → Task 1
- [x] App verified in simulator → Task 12

**Placeholder scan:** No TBD, TODO, or "similar to Task N" patterns. Task 10 requires reading the file first (correct — full content unknown at plan time, but the migration pattern is fully specified).

**Type consistency:** `colors` import from `../../src/constants/theme` used consistently across all migrated files that need runtime color values.

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
| `Icon` | `name`, `size`, `color` | 1906 icons — `round-outlined-radius-2-stroke-1.5` style via `react-native-svg` |

**Extraction rule:** pattern appears in 2+ places → extract to `ui/`. Do not extract speculatively.
**DS compliance:** no `StyleSheet.create()`, no raw hex, import tokens from Tailwind classes only.

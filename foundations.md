# Taisa DS — Foundations

Designer reference for the token system. Source of truth for all Taisa DS token decisions.

---

## How the token system works

Tokens have three layers. You always use the **utility** layer — never primitives or semantic aliases directly.

```
Primitive  →  Semantic alias  →  Utility class
neutral.100  →  muted background  →  bg-muted
```

**Primitives** (nested objects in `mobile/tailwind.config.js` under `theme.extend.colors`) — raw palette values like `neutral.100`, `lime.500`. Never reference these in components.

**Semantic aliases** (flat entries in the same `colors` object) — purpose-named mappings. E.g. `muted: '#f3f3f3'` maps to `bg-muted`. Swap the value here to retheme the whole system.

**Utilities** — the NativeWind class names components actually use. E.g. `bg-muted`, `text-foreground`, `border-border`. These are generated automatically from the `colors` entries.

---

## Decision rule

When choosing a token, always go in this order:
1. **Semantic utility first** — `text-foreground`, `bg-success-subtle`, `border-border`
2. **Named palette as fallback** — `bg-neutral-100` (only if no semantic alias exists for this role)
3. **Gap** — if neither exists, add a new entry to `mobile/tailwind.config.js` under `theme.extend.colors` before using it
4. **Never** — raw hex, raw oklch, arbitrary px, raw Tailwind color utilities like `text-green-700`

---

## Color palettes

| Palette | Purpose |
|---|---|
| `neutral` | Text, backgrounds, borders — the default surface palette |
| `lime` | Primary actions, CTAs |
| `teal` | Accent, secondary brand |
| `blush` | Warm accent |
| `orange` | Warning states |
| `blue` | Info states |
| `red` | Danger, error states |
| `green` | Success states |
| `yellow` | Highlight, caution |

Alpha tokens: `neutral-a4`, `neutral-a8`, `neutral-a16`, `neutral-a20`, `neutral-a30` (neutral-900 at varying opacity).

---

## Semantic color roles

| Role | Utility | Use for |
|---|---|---|
| Page background | `bg-background` | Page/app surface |
| Subtle fill | `bg-subtle` | Hover states, subtle sections |
| Muted fill | `bg-muted` | Input backgrounds, code blocks |
| Card surface | `bg-card` | Cards, panels |
| Primary text | `text-foreground` | Body copy, headings |
| Secondary text | `text-muted-foreground` | Helper text, labels |
| Inverted text | `text-inverted-foreground` | Text on dark/filled backgrounds |
| Default border | `border-border` | Default — neutral-200, cards, inputs, icon CTAs |
| Subtle border | `border-subtle` | Hairline separators (neutral-a8) |
| Strong border | `border-strong` | Darker cases — neutral-300 |
| Primary action bg | `bg-primary` | CTA buttons |
| Primary text on bg | `text-primary-foreground` | Text on CTA buttons |
| Overlay/scrim | `bg-overlay` | Modal backdrops |
| Disabled bg | `bg-disabled` | Disabled inputs/buttons |
| Disabled text | `text-disabled-foreground` | Disabled labels |

Status utilities: add `-subtle` for tinted backgrounds, `-border` for borders, no suffix for text/icon colour.

| Status | Text/icon | Subtle bg | Border |
|---|---|---|---|
| Success | `text-success` | `bg-success-subtle` | `border-success-border` |
| Warning | `text-warning` | `bg-warning-subtle` | `border-warning-border` |
| Danger | `text-danger` | `bg-danger-subtle` | `border-danger` |
| Info | `text-info` | `bg-info-subtle` | `border-info-border` |

---

## Typography scale

Never combine raw Tailwind size + weight utilities. Always use the DS type scale — it encodes size, weight, line-height, and letter-spacing together.

| Class | Size | Weight | Use for |
|---|---|---|---|
| `text-H1` | 28px (desktop) | 600 | Page headings |
| `text-H2` | 24px (desktop) | 600 | Section headings |
| `text-H3` | 20px (desktop) | 600 | Sub-headings |
| `text-xlg-regular` | 18px | 400 | Large body |
| `text-xlg-medium` | 18px | 500 | Large emphasis |
| `text-xlg-semibold` | 18px | 600 | Large strong |
| `text-lg-regular` | 16px | 400 | Default body |
| `text-lg-medium` | 16px | 500 | Body emphasis |
| `text-lg-semibold` | 16px | 600 | Body strong |
| `text-base-regular` | 14px | 400 | UI labels |
| `text-base-medium` | 14px | 500 | UI emphasis |
| `text-base-semibold` | 14px | 600 | UI strong |
| `text-small-regular` | 12px | 400 | Captions, meta |
| `text-small-medium` | 12px | 500 | Caption emphasis |
| `text-small-semibold` | 12px | 600 | Caption strong |

Headings are responsive (mobile → tablet → desktop sizes). Body and label sizes are fixed.

---

## Spacing

Uses the standard 4px multiplier (Tailwind CSS v3 default). `p-1` = 4px, `p-2` = 8px, `p-3` = 12px, `p-4` = 16px, `p-5` = 20px, `p-6` = 24px. Same for `gap-*`, `m-*`, etc.

---

## Border radius

| Class | Value | Use for |
|---|---|---|
| `rounded-1` | 4px | Small UI elements, badges |
| `rounded-2` | 8px | Inputs, buttons |
| `rounded-3` | 12px | Cards, modals |
| `rounded-4` | 16px | Larger cards, panels, sheets |
| `rounded-full` | 1000px | Pills, avatars |

---

## Shadows

`shadow-2xs` → `shadow-xs` → `shadow-sm` → `shadow-md` → `shadow-lg` → `shadow-xl` (lightest to heaviest).

---

## Icons

All icons will come from `@central-icons-react/all` (planned — not yet installed). Browse available icons at the Central Icons Storybook when available.

Zero Lucide icons anywhere in the codebase.

The `<Icon>` wrapper will handle stroke weight automatically based on size. Never pass a stroke colour — the component inherits it from the text colour of its parent.

### Available sizes

| Size | Stroke weight | Use for |
|---|---|---|
| 12px | 1.3 | Tight spaces, dense UI |
| 16px | 1.3 | Inline with `text-small` |
| 20px | 1.5 | Default — inline with `text-base` |
| 24px | 2 | Prominent icons, inline with `text-lg` |
| 32px | 2 | Large feature icons |

### Naming convention

Icons follow the pattern `Icon{Name}{Size}` where size is `Small`, `Medium`, or `Large`. Example: `IconCrossMedium`, `IconArrowRightSmall`, `IconCheckLarge`.

Browse and search in Storybook when available.

---

## When to add a new token

Tokens have a two-sided discipline — too few forces palette fallbacks, too many bloats the semantic layer.

**Add a new semantic + utility token pair when ALL are true:**
- The colour/style serves a clear, reusable interface role
- It will appear in 2+ components or contexts
- It would change in dark mode
- It's an explicit design intent, not a one-off

**Do NOT add a token when ANY are true:**
- It's a one-off decorative use that won't repeat
- An existing token is close enough — adjust the design, not the tokens
- The role is too component-specific to generalise (e.g. `bg-chat-bubble-hover`)
- You're adding it speculatively — YAGNI

**The test:** Can you describe the token's role in one sentence that applies to at least two different components? If not, use the named palette fallback.

**Always add in `mobile/tailwind.config.js`** under `theme.extend.colors`. Use a flat semantic name (e.g., `'my-token': '#hex'`). The NativeWind class (e.g., `bg-my-token`) is generated automatically.

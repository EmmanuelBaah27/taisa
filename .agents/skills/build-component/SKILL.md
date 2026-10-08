---
name: build-component
description: Use when building or editing any component in the Mande Design System — enforces token mapping before code, surfaces gaps, never invents values.
---

# Mande DS — Component Build Protocol

Before writing a single line of code, complete every step below. No exceptions.

## Step 1 — Read live sources

Read these files now:
- `packages/ui/src/tokens/globals.css` — all token values (primitives, semantic aliases, utilities). The only token source of truth.
- `packages/ui/src/stories/icon-categories.js` — available icon names
- `packages/ui/src/components/ui/` — existing components to reuse or extend

## Step 1b — If working from a Figma spec (conditional)

Figma outputs raw values (hex, oklch, arbitrary px) — never use these directly. For each design property:
1. Note the raw value from Figma (e.g. `oklch(93.6% 0.058 32)`, `12px`)
2. Find the matching primitive in `globals.css` `@theme static` block → identify the token name (e.g. `--color-red-100`)
3. Follow the chain upward: primitive (`@theme static`) → semantic alias (`:root`) → utility (`@theme inline`)
4. Record the utility class name — the raw value is only used to find it, never written in code

Proceed to Step 2 only after every Figma value has been resolved to a utility class name.

## Step 1c — Resolve raw values in user prompts (conditional)

If the user's message contains raw values (px sizes, hex colours, numeric font sizes, weight words like "bold" or "medium", vague descriptions like "the lime colour"), resolve them to DS tokens before writing any code. Treat them identically to Figma raw values.

| User says | Write |
|---|---|
| "16px border radius" | `rounded-4` |
| "14px medium text" | `text-base-medium` |
| "the lime / primary colour" | `bg-primary` or `text-primary` |
| "a subtle shadow" | `shadow-xs` or `shadow-sm` |
| "8px gap" | `gap-2` |
| "bold" | the appropriate `-semibold` type scale utility |

Never write the raw value the user specified. Always resolve first.

## Step 2 — Resolve every value to a DS token

Decision hierarchy — follow in order, no exceptions:

```
1. Semantic utility    → text-foreground, bg-success-subtle, border-border
2. Named palette       → bg-neutral-100 (only if use is decorative, one-off, and will never be promoted to DS)
3. Gap found           → flag it, apply criteria below, resolve in Step 4
4. Never               → raw hex, oklch, arbitrary px, raw Tailwind color/size utilities
```

**When a gap is found — two-sided criteria for adding a new token pair:**

Add a semantic utility token when ALL of these are true:
- The colour/style serves a clear, reusable interface role (hover state, selected surface, code block)
- It will appear in 2+ components or contexts
- It would change in dark mode (even though dark mode is deferred)
- It represents an explicit design intent, not a one-off

Do NOT add a semantic utility token when ANY of these are true:
- It's a one-off decorative use that won't repeat
- An existing semantic token is close enough — adjust the design, not the tokens
- The role is too component-specific to generalise (`bg-chat-bubble-hover` won't map anywhere else)
- You're adding it speculatively for future use — YAGNI

**The test:** Can you describe the token's role in one sentence that applies to at least two different components? If not, it doesn't belong in the semantic layer. Use the named palette fallback instead.

**Colour token contrast gate (WCAG 2.2 AA):**
Before confirming any new foreground/background colour pair, verify it meets the applicable contrast ratio:
- Text colour on background: 4.5:1 (normal text) or 3:1 (large text / bold ≥ 14px)
- UI boundary colour (border/outline) against adjacent: 3:1

Do not add a semantic colour alias that fails these ratios. If the raw palette value doesn't pass, choose a passing shade first, then create the alias from that shade.

**Gap resolution — always a paired action:**

When criteria confirm a new token is warranted, add both layers in a single edit to `globals.css`:
1. Semantic alias in `:root` → `--semantic-{role}: var(--color-{palette}-{shade})`
2. Tailwind utility in `@theme inline` → `--color-{name}: var(--semantic-{role})`

Never add one without the other. No utility without a semantic alias (exposes primitives). No semantic alias without a utility (unusable in Tailwind).

Then update `docs/design-system/foundations.md` as the designer-facing record.

Flag every gap. Never approximate, never invent. Present the full mapping table + all open questions. Wait for confirmation before writing code.

## Step 3 — Check existing implementations

Before building, check:
- `packages/ui/src/components/ui/` — does this component or a close relative already exist?
- `packages/ui/src/index.ts` — what's already exported?
- Existing story files — what variants are already covered?

Polish existing surfaces rather than building parallel APIs.

## Step 4 — Surface gaps + update globals.css

For any token gap confirmed by the Step 2 criteria: add both the semantic alias (`:root`) and the Tailwind utility (`@theme inline`) to `packages/ui/src/tokens/globals.css` as a single paired edit. Then update `docs/design-system/foundations.md`. Only then use the utility in component code.

## Step 5 — Accessibility check (WCAG 2.2 AA)

Compliance baseline: **WCAG 2.2 Level AA** (ISO/IEC 40500:2025). Before writing JSX, verify the component design covers:
- **Labels** — all interactive elements have accessible labels (aria-label, aria-labelledby, or visible text)
- **Keyboard** — Tab to focus, Enter/Space to activate, Escape to dismiss (where applicable)
- **Focus management** — overlays trap focus on open, restore focus to trigger on close
- **Focus indicators** — visible ring with ≥ 2px perimeter; focused vs unfocused state ≥ 3:1 contrast (SC 2.4.11)
- **Touch targets** — interactive elements ≥ 24×24px hit area (SC 2.5.8); aim for 44×44px on mobile
- **Reduced motion** — use `useReducedMotion()` from `motion/react` for any animated component
- **Colour** — meaning is never conveyed through colour alone; contrast ratios verified (4.5:1 text, 3:1 UI boundaries)

## Step 5b — Copy review (conditional)

If the component contains any user-facing strings — labels, messages, CTAs, placeholders,
empty state copy, tooltips, error text, or notification content — invoke `mande-copywriter`
before finalizing. Do not hardcode copy without running it through the skill.

This applies to strings written directly in JSX, passed as props, or defined as constants.
If the copy already exists and was not written in this session, use `mande-copywriter` to
review it and flag any violations.

## Step 6 — Promotion check

After playground validation passes (golden path tested visually), assess against all criteria:
- [ ] Validated in playground — golden path tested visually
- [ ] All tokens resolve — zero raw utilities anywhere in the component
- [ ] API is generic — reusable across surfaces, no playground-specific props or assumptions
- [ ] Accessibility check passes (Step 5 fully met)

If all criteria pass, prompt the user:

> "This component looks promotion-ready. Want me to promote it to `packages/ui/`?"

Wait for user confirmation before doing anything. If confirmed, invoke `promote-to-ds`.

---

## Hard rules

- **No raw values ever** — no hex, no oklch, no arbitrary `px`, no raw Tailwind color/size utilities (`text-green-700`, `bg-gray-100`, `text-sm`, `font-bold`)
- **No raw typography** — never combine `text-sm font-semibold`; always use `text-base-semibold`
- **Semantic before palette** — `text-foreground` not `text-neutral-900`; always check for a semantic utility first
- **No invented tokens** — if it's not in `globals.css`, flag it as a gap and add it there before using it
- **Icons** — only `@central-icons-react/all` via `<Icon name="..." size={12|16|20|24|32} />`. Zero Lucide. Never pass stroke colour — the wrapper handles it automatically. Stroke scales with size (`12→1.3, 16→1.3, 20→1.5, 24→2, 32→2`).
- **Icon button touch target** — all interactive icons must reach a 24×24px hit area (WCAG 2.2 AA SC 2.5.8). Add padding to reach the minimum: `p-[6px]` for 12px icons, `p-1` for 16px, `p-0.5` for 20px (already close), none needed for 24px+. Always pair padding with a matching negative margin (`-m-1`, `-m-[6px]`, etc.) so the hit area sits behind the icon without affecting surrounding layout — the icon appears flush, the touch zone does not.
- **No `ring-offset-background`** — this token does not exist in Mande
- **No dark mode** — deferred; never add `dark:` variants
- **Motion** — `motion` library (v12) for custom animation; `tw-animate-css` for Radix `data-state` overlays. Spring presets in `tokens/motion.ts`. Default to springs; ease-out for duration-based.
- **Stories** — group as `Components/{Form|Display|Navigation|Overlays|Feedback|Layout}/{Name}`; foundations as `Foundations/{Name}`

# Light Design System

**Track:** Platform
**Status:** Ready to plan

---

## What is it?

Replaces the current dark-theme token set in `tailwind.config.js` and `global.css` with the Mande DS light-mode token system. Migrates every existing screen and DS component to use the new token class names. Once done, every subsequent screen build inherits a consistent, documented design language automatically.

**Primary action color:** `lime-500` (`oklch(89% 0.205 119)`) — the Mande DS default. Replaces the old Taisa purple (`#7C6FFF`).

**Typeface:** Strichpunkt Sans (Google Font). Replaces Inter. Same type scale configuration — sizes, weights, line-heights, letter-spacing all unchanged. Inter-specific OpenType feature settings and `font-optical-sizing` are removed.

## Why now?

Every Product build from Phase 1 onwards inherits tokens from here. The persistent input bar, chat UI, Logs tab, and Account tab all depend on this being in place first. Without it, each new screen introduces ad-hoc color decisions that need cleanup later. This is the foundation — nothing else ships before it.

## Acceptance criteria

- [ ] `tailwind.config.js` contains the full Mande DS light token set — neutral, lime, teal, blush, orange, blue, red, green, yellow palettes + semantic aliases — in a format compatible with NativeWind v4 (Tailwind v3 `theme.extend`)
- [ ] Old dark-only tokens (`background: '#0A0A0F'`, `surface: '#13131A'`, `text-primary: '#F0F0F8'`, etc.) are fully removed from `tailwind.config.js`
- [ ] Mande DS typography classes (`text-H1`, `text-H2`, `text-H3`, `text-lg-regular`, `text-base-medium`, `text-small-semibold`, etc.) are defined in `global.css` and render correctly in NativeWind with the right size, weight, and line-height
- [ ] Font family is set to Strichpunkt Sans — Inter-specific OpenType character variant settings (`cv01`–`cv09`) and `font-optical-sizing` are removed
- [ ] Mande DS radius tokens (`rounded-1` through `rounded-4`, `rounded-full`) are available as Tailwind utilities
- [ ] All existing screens (Today, Threads, You, Thread detail, Recording, Onboarding) use Mande DS class names — no old dark-token class names remain
- [ ] All DS components (Badge, Button, Card, Input) updated to Mande DS class names
- [ ] No `StyleSheet.create()` calls in any migrated file
- [ ] `docs/design-system.md` updated — replaces old dark token docs with Mande DS as the source of truth, referencing `foundations.md` as the designer reference
- [ ] App renders correctly in the iOS Simulator after migration — no blank screens, token resolution failures, or invisible text

## Out of scope

- Dark mode — light only; `.dark` overrides are a later phase
- Any new screens, components, or layout changes — token name migration only
- `foundations.md` moving into the repo — stays at root as a reference document
- Tab icons, navigation restructure, or any other Product-layer changes

# Design System Migration Audit

**Baseline commit:** `34834aad693242a4b4274715d575525c9a79fab7`

This inventory records the violations present at Build start. Test and Storybook files are included because the final verifier also governs visual examples; test fixtures may receive exact exceptions where a literal is the behavior under test.

## Typography violations

| Area | Files | Raw Text import | Legacy size/weight | Arbitrary size |
|---|---|---:|---:|---:|
| App routes | `(tabs)/chats.tsx`, `(tabs)/index.tsx`, `(tabs)/you.tsx`, `_layout.tsx`, `onboarding/index.tsx`, `thread/[id].tsx` | Yes | Yes | Present in current inventory |
| Legacy shared presentation | `DigestCard`, `SearchBar`, `TaisaCard`, `ThemeTag`, `ThreadResumeAction`, `ThreadRow`, `WorkspaceHeader` | Yes | Yes | Present in current inventory |
| DS foundations | `Badge`, `Button`, `Card`, `Input`, `ChatHeader`, `ChatListRow`, `ChatSurfaces`, `TaisaReplyCard`, `ThreadMessage` | Yes | Yes | Present in current inventory |
| Navigation and recording | `ActiveRecordingSurface`, `BottomNavBar`, `GlowDevSheet`, `PersistentNavigationCapsule`, `SelectedNavigationItem`, `VoiceComposer`, `VoiceDraftStrip`, `VoiceReactiveTimestamp` | Yes | Yes | Present in current inventory |
| Visual stories/tests | stories and contract tests reported by the baseline `rg` command | Yes | Yes | Present in current inventory |

## Color violations

| Area | Files | Raw color | Palette utility | Required semantic role |
|---|---|---:|---:|---|
| App routes | `(tabs)/_layout.tsx`, `(tabs)/you.tsx`, `_layout.tsx`, `thread/[id].tsx` | Yes | Yes | app surface, text, overlay |
| Legacy shared presentation | `DigestCard`, `TaisaCard`, `WorkspaceHeader` | Yes | Yes | surface, text, border |
| DS foundations | `Badge`, `Button`, `Card`, `GlowDevSheet`, `SelectedNavigationItem` | Yes | Yes | action, status, surface, text |
| Native material/rendering | `MorphSurface`, `liquidGlass`, `BottomNavBar` | Yes | Limited | platform material, animation, shadow |
| Visual stories/tests | stories and tests reported by the baseline `rg` command | Yes | Yes | semantic fixture roles or exact test exception |

## Component classification

| Component | Reuse | Modify | Move to ui | Move to features | Screen-specific |
|---|---:|---:|---:|---:|---:|
| `Button`, `Input`, `Card`, `Badge`, `Icon` | Yes | Yes | No | No | No |
| Liquid-glass action surfaces | Yes | Yes | No | No | No |
| Navigation, chat, and recording surfaces | Yes | Yes | No | No | No |
| `DigestCard`, `SearchBar`, `ThemeTag`, `ThreadRow` | Yes | Yes | Yes when presentation-only | No | No |
| `TaisaCard`, `ThreadResumeAction`, `VoiceButton` | Yes | Yes | Conditional on repeated presentation contract | Yes when domain state remains | No |
| `WorkspaceHeader` | Yes | Yes | Yes | No | No |
| Route shells and journey composition | No | No | No | No | Yes |
| Semantic `Text` | New foundation | Yes | Yes | No | No |
| `Screen`, `Stack`, `Row`, `Section`, `Divider` | Only after two confirmed uses | Conditional | Yes | No | No |

The initial shared-component pass retained existing file locations to avoid mixing navigation/store separation with visual migration. `DigestCard`, `TaisaCard`, `ThreadResumeAction`, `ThreadRow`, and `VoiceButton` remain feature/domain wrappers because they own routing or state. `SearchBar`, `ThemeTag`, and the presentational portion of `WorkspaceHeader` are candidates for a later physical move only when a second active consumer justifies it; all now consume semantic foundations.

## Technical exceptions

| File | Rule | Native API reason | Owner | Review date |
|---|---|---|---|---|
| `mobile/src/components/ui/MorphSurface.tsx` | raw color and numeric rendering values | Native animated material interpolation requires resolved color strings and numeric geometry | Design system foundation | 2026-09-25 |
| `mobile/src/components/ui/liquidGlass.ts` | raw platform material values | Platform material capability and shadow fallbacks require native values | Design system foundation | 2026-09-25 |
| `mobile/src/components/ui/BottomNavBar.tsx` | numeric animated style values | Reanimated geometry cannot be expressed as static NativeWind utilities | Design system foundation | 2026-09-25 |
| `mobile/src/components/ui/__tests__/liquidGlass.test.ts` | color literals in assertions | Contract test must assert the exact platform fallback output | Design system foundation | 2026-09-25 |
| `mobile/src/components/ui/__tests__/SecondaryIconButton.test.ts` | color literals in assertions | Contract test verifies resolved native icon color | Design system foundation | 2026-09-25 |

## Migration order

1. Freeze semantic token and typography contracts.
2. Introduce semantic `Text` and align foundational components.
3. Add the fixture-tested verifier and exact exception registry.
4. Migrate shared presentation before route consumers.
5. Migrate routes by onboarding, Home/Chats/You, then chat/recording/thread journeys.
6. Remove every violation from this baseline or retain it only through a dated exact-file exception.

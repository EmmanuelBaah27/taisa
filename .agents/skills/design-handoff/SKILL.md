---
name: design-handoff
description: >
  Use when Baah shares any visual design reference for a feature — Figma link,
  screenshots, annotated designs, or sketches (photo or scan) — before writing
  an implementation plan. Sits between the Design and Plan stages of the workflow.
  Triggered by Baah sharing a design artifact or saying "here's the design",
  "I've sketched this", "I've designed this", or "ready to plan" after a design share.
---

# Design Handoff

Receives a design from Baah, interprets it against the existing codebase and
design system, and produces a structured brief ready to hand directly to
`superpowers:writing-plans`. Use `design:design-system` to audit and extend the
system. Use `design-system-patterns` for contract architecture, styles,
foundations, compatibility, and migration. This skill supplies Taisa paths,
authority, approval gates, and native review requirements.

---

## Design source

Three paths — same process, same output. Precision varies; DS tokens fill the gaps.

**Path A — Figma or screenshots:** Baah shares a Figma link or exported screens.
The agent reads via Figma MCP (`get_design_context`) or reads the image directly.
Highest precision — token coverage check is most important here.

**Path B — Sketches:** Baah shares a photo or scan of a hand-drawn sketch.
The agent reads the image, interprets layout intent and component shapes.
Treat as directional — note in brief: "Source is a sketch. Implementation latitude
applies for exact spacing and layout. Token values used where sketch is ambiguous."

**Path C — Visual Companion:** Baah completes a brainstorming session with visual
companion output. The agent reads the agreed mockups and chat decisions.
Note in brief: "Design is directional — implementation latitude applies. Device QA
is the real sign-off."

In all paths: DS tokens carry the precision the design source doesn't provide.

## Step-by-step

```
1. READ  → approved Scope in the matching Linear issue/document
2. READ  → Work Map and Product Discussion decisions
3. ROUTE → invoke `design:design-system` in audit or extend mode
4. ROUTE → invoke `design-system-patterns` for architecture and lifecycle
5. SCAN  → the platform registry, contracts, styles, consumers, and foundations
6. MAP   → each requirement to reuse / extend / create / exception
7. CHECK → compatibility, contexts, accessibility, and migration
8. FLAG  → Product, Platform, and backend implications
9. DRAW  → Product architecture/state diagram with layman-first labels
10. ASK  → max 3 questions, only genuine ambiguities
11. OUTPUT → structured handoff brief (format below)
12. CHAIN → after Baah confirms brief, invoke writing-plans automatically
```

## Contract taxonomy

Classify each design-system contract at one level:

- **Foundations:** atomic semantic values with no structure or behavior.
- **Assets:** renderable resources with no interaction or layout ownership.
- **Behaviors:** reusable interaction, state, accessibility, and adaptation rules.
- **Styles:** presentation recipes with no view hierarchy or interaction ownership.
- **Components:** reusable UI structures that compose approved lower-level contracts.
- **Platform adapters:** the only approved translation boundary to raw platform APIs.

Styles compose foundations and assets. Existing or new components consume approved styles and
behaviors. Product surfaces consume registered contracts and own business logic. Product code
must not restyle a component locally; extend or create the shared style or component contract.

## Contract mapping

For every distinct UI element in the design:

| Treatment | Use when | Required evidence |
|---|---|---|
| **Reuse** | One registered contract covers the requirement | Contract, supported capability, and consumers |
| **Extend** | An existing contract remains coherent with one added capability | Missing capability, affected consumers, compatibility |
| **Create** | Extension would make every existing contract contradictory | Compared contracts, reusable purpose, owner, lifecycle |
| **Exception** | A system-owned boundary cannot use a coherent registered contract | Narrow scope, owner, reason, expiry, removal issue |

Use exactly one treatment. Missing coverage stops before Product code until Baah approves the
treatment in Linear. Do not create a component because of copy, callback, size, width, or one
screen. Do not create a style for a local visual override.

## Compatibility and contexts

Classify a change as additive, intentional system-wide restyle, or breaking. Additive changes
preserve current defaults. System-wide restyles list and review every dependent consumer.
Breaking changes require a replacement contract, migration, deprecation, and removal condition.
Compatibility aliases stay inside shared contracts and cannot become new Product dependencies.

Review appearance, accessibility settings, device class and input method, and locale and content
length. Record unsupported contexts as gaps, not implied support.

---

## Backend implications

Scan the design for elements that reveal backend requirements not captured in the scope doc:

- New data displayed → is there an API endpoint that returns it?
- User actions → is there a route that handles them?
- Loading / empty states → does the backend return the signals needed to drive them?
- Context-dependent behavior → does the backend pass the context param needed?

List any gaps. These go into the plan as platform prerequisites if not already covered.

---

## Handoff brief format

```markdown
# Design Handoff — [Feature Name]

**Scope:** [Linear issue/document URL]
**Design source:** [Figma link or screenshot reference]
**Status:** Draft / Confirmed
**Last updated:** YYYY-MM-DD

---

## Design-system contract inventory

| Requirement | Contract type | Treatment | Registered contract | Capability evidence | Compatibility / migration |
|---|---|---|---|---|---|
| [requirement] | [taxonomy] | [reuse/extend/create/exception] | [file/name] | [states/behavior/contexts] | [evidence] |

## Product architecture and states
[Mermaid diagram showing the user-visible flow and real screens, components, Platform
contract, states, and failure boundaries.]

## Design-system gaps and exceptions
- [List each unavailable contract and approval, or "None"]

## Backend implications
- [List any API gaps revealed by the design, or "None — all data already available"]

## Open questions
- [Max 3 — only genuine ambiguities that block the plan]

## Ready for plan
[One sentence confirming the design is understood and the plan can be written,
or listing what needs to be resolved first]
```

---

## Clarifying questions

Only ask what would block the plan. Never ask about things that are clear.

| Question | Why it matters |
|---|---|
| Which interaction triggers this state? | Needed to spec the event handler |
| Is this a new component or reuse of X? | Determines build scope |
| Does this data come from an existing endpoint? | Determines platform dependency |

---

## [TAISA-SPECIFIC]

*Taisa-specific context. Replace this section when reusing on another project.*

### Workflow stage context

```
ORIENT → DISCUSS → SCOPE → PRODUCT DESIGN HANDOFF → PLAN → BUILD → REVIEW + QA
```

This skill sits between approved **Scope and Plan** for Product slices. Discussion establishes
experience requirements; this skill maps visual evidence to layouts, components, tokens, and
interactions. It fires automatically when:
- Baah shares a Figma link or screenshots (Path A)
- A visual companion brainstorming session ends and Baah agrees the mockups (Path B)

Triggers on any visual reference — Figma link, screenshot, sketch photo, or visual
companion output. Its output — particularly the Component inventory — is the DS foundation
layer for the implementation plan. `writing-plans` reads the brief and builds the plan DS
section from it.

After Baah confirms the brief, the agent invokes `writing-plans` automatically.
Baah does not need to say "ready to plan."

### Platform routing

Choose the shipping surface first. Do not use legacy paths for native work.

| Surface | Shared contracts | Product consumers | Verification |
|---|---|---|---|
| SwiftUI iPhone/iPad | `apple/Packages/TaisaFoundation/Sources/TaisaDesignSystem/` | `apple/TaisaApp/` | Native DS, package/Xcode, browser simulator, accessibility |
| Legacy React Native | `mobile/src/components/` and `mobile/tailwind.config.js` | `mobile/src/` | NativeWind, legacy tests, legacy preview |

For SwiftUI, inspect the shared package, Central Icons, existing consumers, and semantic roles.
For legacy work, use NativeWind and the documented legacy design system. Never infer that a
contract on one platform exists on the other.

### Legacy component locations

| Bucket | Path | Contains |
|---|---|---|
| Primitives | `mobile/src/components/ui/` | Button, Card, Input, Text, Badge, Tag |
| Layout | `mobile/src/components/layout/` | Screen, Stack, Row, Divider, Section |
| Domain | `mobile/src/components/features/` | EntryCard, GoalTag, CoachNote, ModeChip |

### Constraints — flag any design element that would require these

| Constraint | Rule |
|---|---|
| Dark background colors | Light theme only for now |
| `StyleSheet.create()` | NativeWind classes only |
| New native modules | Expo managed workflow — flag before including |
| Auth-dependent UI | v1 is device UUID only — no user accounts |

### Key reference docs

| Need | Read |
|---|---|
| Design tokens | `docs/design-system.md` |
| Approved Scope | Matching Taisa Linear issue or attached document |
| Live priority / dependencies | Matching Taisa Linear issue and milestone |
| API shape | `docs/api.md` |
| Workflow stages | `docs/workflow.md` |

Write the confirmed handoff to the matching Linear issue or attached Linear document.
Repository feature scopes, specifications, plans, and QA notes are historical input only;
never update or cite them as the live Scope, Plan, stage, or approval artifact.

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
`superpowers:writing-plans`.

---

## Design source

Three paths — same process, same output. Precision varies; DS tokens fill the gaps.

**Path A — Figma or screenshots:** Baah shares a Figma link or exported screens.
Claude reads via Figma MCP (`get_design_context`) or reads the image directly.
Highest precision — token coverage check is most important here.

**Path B — Sketches:** Baah shares a photo or scan of a hand-drawn sketch.
Claude reads the image, interprets layout intent and component shapes.
Treat as directional — note in brief: "Source is a sketch. Implementation latitude
applies for exact spacing and layout. Token values used where sketch is ambiguous."

**Path C — Visual Companion:** Baah completes a brainstorming session with visual
companion output. Claude reads the agreed mockups and chat decisions.
Note in brief: "Design is directional — implementation latitude applies. Device QA
is the real sign-off."

In all paths: DS tokens carry the precision the design source doesn't provide.

## Step-by-step

```
1. READ  → scope doc for the feature                    [TAISA: docs/features/<name>.md]
2. READ  → design system tokens                         [TAISA: docs/design-system.md]
3. SCAN  → existing components                          [TAISA: mobile/src/components/]
4. MAP   → every design element to: reuse / modify / new
           (this output becomes the DS layer of the implementation plan)
5. CHECK → token coverage — does the design use tokens that exist?
6. FLAG  → backend implications the design reveals
7. ASK   → max 3 questions, only genuine ambiguities
8. OUTPUT → structured handoff brief (format below)
9. CHAIN → after Baah confirms brief, invoke writing-plans automatically
```

---

## Component mapping

For every distinct UI element in the design:

| Design element | Verdict | Notes |
|---|---|---|
| Matches existing component exactly | **Reuse** | Name the file |
| Mostly matches but needs a prop or variant | **Modify** | Name the file, name the change |
| No match — new build needed | **New** | Name it, note which `ui/` or `features/` bucket |

**Extraction rule:** if a pattern appears in two or more screens, it becomes a `ui/` component. Don't propose extraction speculatively — only when the second use exists or is confirmed in this design.

---

## Token coverage check

Cross-reference every color, spacing, and radius value in the design against the token list.

| Token type | Where to check | Flag condition |
|---|---|---|
| Colors | `tailwind.config.js` + `docs/design-system.md` | Design uses hex not in the token set |
| Spacing | spacing scale in `docs/design-system.md` | Design uses value not on the scale |
| Border radius | radius scale in `docs/design-system.md` | Design uses value not on the scale |
| Typography | type scale in `docs/design-system.md` | Design uses size/weight not defined |

Flag gaps to Baah before the plan is written — the plan should never introduce raw hex values or magic numbers.

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

**Scope doc:** docs/features/<name>.md
**Design source:** [Figma link or screenshot reference]

---

## Component inventory

| Element | Verdict | File / Name |
|---|---|---|
| [element] | Reuse | mobile/src/components/... |
| [element] | Modify | mobile/src/components/... — add [prop] |
| [element] | New | mobile/src/components/ui/[Name].tsx |

## Token gaps
- [List any design values not covered by existing tokens, or "None — all values covered"]

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
SCOPE → DESIGN → PLAN → BUILD → REVIEW + QA
```

This skill sits at the **Design → Plan handoff**. It fires automatically when:
- Baah shares a Figma link or screenshots (Path A)
- A visual companion brainstorming session ends and Baah agrees the mockups (Path B)

Triggers on any visual reference — Figma link, screenshot, sketch photo, or visual
companion output. Its output — particularly the Component inventory — is the DS foundation
layer for the implementation plan. `writing-plans` reads the brief and builds the plan DS
section from it.

After Baah confirms the brief, Claude invokes `writing-plans` automatically.
Baah does not need to say "ready to plan."

### Design system

- **Theme:** Light first. No dark tokens in new components.
- **Styling:** NativeWind only — no `StyleSheet.create()`.
- **Token file:** `docs/design-system.md` + `mobile/tailwind.config.js`
- **Token naming in classes:** `bg-background`, `bg-surface`, `text-text-primary`, `text-accent`, etc.

### Component locations

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
| Feature scope | `docs/features/<name>.md` |
| Roadmap / dependencies | `docs/roadmap.md` |
| API shape | `docs/api.md` |
| Workflow stages | `docs/workflow.md` |
</content>

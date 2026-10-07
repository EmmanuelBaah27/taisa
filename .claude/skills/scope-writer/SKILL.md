---
name: scope-writer
description: >
  Use when a feature idea needs a formal scope doc — user describes a feature,
  says "scope this", "let's define this", or roadmap shows "Needs scoping".
  Reads current project state, asks targeted clarifying questions, flags missing
  or weak acceptance criteria, and writes the completed doc to the correct location.
---

# Scope Writer

Converts raw feature ideas into agreed scope docs. Reads the roadmap, fills gaps
with targeted questions, drafts a complete scope doc, and writes it to the right place.

---

## Step-by-step

```
0. TIER    → assess feature size: Quick / Standard / Full          [TAISA: see Feature tiers]
1. DEDUP   → check docs/backlog.md for existing capture            [TAISA: docs/backlog.md]
2. READ    → roadmap + any docs mentioned in the feature idea      [TAISA: docs/roadmap.md]
3. MAP     → Standard/Full: Work Map with Platform / Product /
             Integration slices, sizes, dependencies, and pickup order
4. SELECT  → Baah selects the next slice
5. DISCUSS → show its track-specific Discussion Map; ask one question at a time
6. DRAFT   → complete scope doc using the format below
7. FLAG    → check every AC against the quality rules before showing
8. WRITE   → output to correct location                           [TAISA: docs/features/<name>.md]
9. UPDATE  → roadmap status: "Needs scoping" → "Ready to plan"   [TAISA: docs/roadmap.md]
10. CHAIN  → after Baah agrees scope doc:
             Platform track → invoke writing-plans directly
             Product track  → prompt Baah for design, then invoke design-handoff
```

Work and Discussion Maps orient; Scope and Plan approvals remain separate.

---

## Clarifying questions

Ask only what's missing from the idea. Never interrogate a clear request.

| Question | Why it matters |
|----------|----------------|
| Platform, Product, or both? | Determines which sections apply |
| Why now — what does this unblock? | Required "Why now?" section |
| What does "done" look like? | Source of acceptance criteria |
| What is explicitly NOT included? | Required "Out of scope" section |
| What Platform work does this depend on? *(Product only)* | Required "Platform dependencies" section |

---

## Scope doc format

```markdown
# [Feature Name]

**Track:** Platform / Product / Both
**Status:** Ready to plan
**Last updated:** YYYY-MM-DD
**Work Map:** [path, or "Inline — Standard tier"]

---

## At a glance
[Mermaid architecture diagram with layman-first labels and real technical components in
secondary labels. Show ownership, data movement, storage, and failure boundaries.]

## Discussion decisions
- [Decision reached]
- [Deferred question, owner, and resolution point]

## What is it?
[2–4 sentences. What this does and why it matters to the user.]

## Why now?
[What this unblocks or what urgency drives it. Why this phase, not later.]

## Acceptance criteria
- [ ] [Observable behavior — user sees / system returns / endpoint responds]
- [ ] [Happy path completes successfully end-to-end]
- [ ] [Failure/edge case handled, or explicitly listed in Out of scope]

## Platform dependencies
*(Product features only — remove section for Platform-only work)*
- [ ] [Platform item that must reach Build before this can start]

## Out of scope
- [What this explicitly does not include]
- [Anything that might be assumed but isn't intended]
```

---

## AC quality flags

Check every acceptance criterion before finalizing. Block or flag as needed.

| Condition | Action |
|-----------|--------|
| No ACs at all | **BLOCK** — cannot scope without at least 3 testable ACs |
| Describes implementation, not behavior | **FLAG** — rewrite as: "User sees…", "System returns…", "Endpoint responds…" |
| No happy path AC | **FLAG** — add explicit "primary flow completes successfully" criterion |
| No error/edge case AC | **FLAG** — add one, or move to Out of scope with a note |
| AC is not verifiable | **FLAG** — ask: "How would we test this?" Rewrite until answerable |

---

## [TAISA-SPECIFIC]

*Everything below is Taisa-specific. When reusing this skill on another project,*
*replace this section with your project's constraints, track definitions, status*
*vocabulary, and document locations. The step-by-step, questions, format, and AC*
*flags above are fully generic.*

### Constraints — flag any AC that would require these

These are blocked by design in v1. Flag the AC to Baah before including it.

| Constraint | Rule |
|------------|------|
| Auth / user accounts | v1 uses device UUID only — `x-user-id` header, no auth middleware |
| Non-SQLite database | SQLite only — no Postgres, no migrations system |
| Native builds | Expo managed workflow only — no `expo run:ios` or `eject` |
| `StyleSheet.create()` | NativeWind only for all new or rebuilt UI components |

### Track definitions

- **Platform** — AI, backend, API, persistence, infrastructure, and Product-facing contracts.
- **Product** — UI, screens, components, interaction, and device experience.
- **Integration** — shared cross-track wiring and verification, not a third track.

Independent Product foundation may proceed after Product Plan approval. Contract wiring and
live-data integration wait for the named Platform dependency.

### Roadmap status vocabulary

| Status | Meaning |
|--------|---------|
| Needs scoping | No scope doc written |
| Ready to plan | Scope doc written and agreed |
| In plan | Implementation plan being written |
| In build | Active development |
| Done | Shipped and merged |

### Document locations

| Document | Location |
|----------|----------|
| Scope docs | `docs/features/<feature-name>.md` |
| Roadmap | `docs/roadmap.md` |
| Implementation plans | `docs/superpowers/plans/<name>.md` *(written at Plan stage, not now)* |

### Feature tiers

| Tier | Signal | Scope doc? |
|---|---|---|
| Quick (< 1h) | Single change, no new DS components, no Platform work | No — Claude states intent in one line and builds |
| Standard (half day) | New screen or significant component | Inline Work and Discussion Maps; lightweight scope and plan with separate approvals |
| Full (multi-day) | New Platform work, new DS components, complex Product | Full scope doc, all gates |

Claude states tier before scoping: "This is a Standard build."
Baah can override: "treat this as Quick" or "go Full on this."

### Workflow stage context

```
ORIENT → DISCUSS → SCOPE → PLAN → BUILD → REVIEW + QA
```

This skill handles **SCOPE**. After scope is agreed:
- **Platform track** → `writing-plans` fires automatically
- **Product track** → Claude prompts for design. When design is shared, `design-handoff` fires.
  After brief is confirmed, `writing-plans` fires.

Baah never needs to name the next skill — Claude chains forward automatically.

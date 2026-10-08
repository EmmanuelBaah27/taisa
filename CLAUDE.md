# Taisa — Claude Code Context

Taisa is a personal AI career companion for Baah. The shipping direction is a native SwiftUI
iPhone/iPad product with encrypted device-authoritative data. The React Native client remains
legacy migration source until its required behavior and unique work are safely accounted for.

**Stack:** Swift 6/SwiftUI, encrypted SQLite/GRDB/SQLCipher, Node/Express services where still
required, plus the legacy React Native/Expo client during migration.

---

## Critical Constraints

Do not violate these without explicit instruction:

- **Client authority is Swift** — active iPhone/iPad product code lives under `apple/`; React Native survives only in Git history and frozen migration evidence.
- **SQLite only** — `backend/src/db/connection.ts`. No migrations system. Add columns via `ALTER TABLE` or update `schema.sql` and note manual migration needed.
- **Native Apple workflow** — use the generated Xcode project and `scripts/native-apple/verify-all.sh`; do not hand-edit generated project output.
- **Root workspace** — npm covers `backend/` and `shared/` only. Swift packages and Xcode targets live under `apple/`.
- **Native design system for all new UI** — use typed Swift tokens/components. See `docs/design-system.md`.

---

## Session Continuity

- Include a short **Last activity summary** only in the first response of a session.
- Keep it to 1-3 bullets covering the most recent meaningful actions (what was checked, changed, or decided).
- If no code was changed yet, explicitly say so.

---

## The Critical Gap

**Product docs describe a chat interface with four coaching modes (Mirror / Nudge / Challenge / Direct). What's built is a voice journaling loop with one-shot Claude analysis. Do not conflate them.**

The Senior Self persona is NOT yet implemented. The current `journalProcessor.ts` is a structured analyser. The build guide for closing this gap is in `docs/agent-persona.md` Part 3.

---

## Where to Look

| I need to... | Read |
|---|---|
| Reorient across sessions | `docs/project-memory.md` |
| Understand current build state | `docs/v1-status.md` |
| Understand system architecture | `docs/architecture.md` |
| Touch the database | `docs/data-model.md` |
| Add or modify an API endpoint | `docs/api.md` |
| Work on Claude prompts or AI behaviour | `docs/agent-persona.md` |
| Build or modify UI components | `docs/design-system.md` |
| Understand the product vision | `docs/product/01-product/product-brief-001.docx` |
| Follow the build workflow | `docs/workflow.md` + `taisa-workflow` skill |

---

## Workflow

Load these shared workflow files at the start of every scope, plan, build, review, or Ship task:

1. `docs/workflow.md` — human-readable source of truth
2. `.claude/skills/taisa-workflow/SKILL.md` — operational orchestrator
3. `docs/project-memory.md` — durable context entry point
4. `AGENTS.md` — Codex automatic entry point

Linear is the sole live authority. It owns roadmap, actionable work, stage, ownership,
dependencies, blockers, Scope, Plan, acceptance, discussion, and gate evidence. Git remains
authoritative for code-coupled constraints, contracts, decisions, migrations, and verification.
The orchestrator maps Taisa's stages to required Superpowers skills. Baah approves Scope,
Plan, physical-device judgment, and Ship; agents handle routine Linear, Git/GitHub,
verification, and code-coupled documentation within those approvals.
After reading the memory index, load only the accepted decisions, reusable learnings, and
canonical domain documents relevant to the current task.

If Linear is unavailable, use the offline fallback in `docs/workflow.md`: continue only
already-approved work supported by trusted recent Scope/Plan context and Git evidence, and do
not start or advance work until Linear is reconciled.

---

## Backend Pattern

Every AI feature: route → agent → prompt builder → `callClaudeJson` → DB write.
Reference: `backend/src/services/claude/journalAgent.ts` + `backend/src/prompts/system/journalProcessor.ts`.
Full walkthrough: `docs/architecture.md` § "How the Backend Calls Claude".

---

## Common Commands

```bash
# Start backend (from repo root)
npm run backend

# Start mobile (from repo root)
npm run mobile

# Install a mobile dependency
cd mobile && npm install <package>

# Install a backend dependency
npm install <package> --workspace=backend
```

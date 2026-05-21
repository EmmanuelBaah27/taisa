# Taisa Roadmap

**Last updated:** 2026-05-14
**Design direction:** Light theme first. Voice primary, text secondary.
**Two tracks:** Platform (AI + backend) runs one step ahead of Product (UI).

---

## Active work

| Feature | Track | Stage | Branch | Blocked on |
|---|---|---|---|---|
| Light design system | Platform + Product | Review (device QA) | feature/light-design-system | — |
| Persistent input bar + Chat UI | Platform + Product | Plan | — | Light design system shipped |

---

## How to read this

Each phase lists platform work and product work in parallel. A product item marked **(blocked on platform)** cannot enter Build until the platform item it depends on is complete.

Scope docs live in `docs/features/`. Implementation plans live in `docs/superpowers/plans/`.

---

## Phase 1 — Foundation

Everything else is blocked on this phase.

### Platform
| Work | Scope doc | Status |
|---|---|---|
| Light design system — Taisa DS tokens, Strichpunkt Sans, migrate all screens | light-design-system.md | Review (device QA) |
| `@react-native-voice/voice` + `useLiveTranscription` hook | persistent-input-bar.md | Ready to plan |

### Product
| Work | Scope doc | Status | Blocked on |
|---|---|---|---|
| Persistent input bar + chat UI (unified screen) | persistent-input-bar.md | In Plan | Light design system, useLiveTranscription |

---

## Phase 2 — Core pages

Run platform and product in parallel where possible.

### Platform
| Work | Scope doc | Status |
|---|---|---|
| `chatProcessor.ts` — Senior Self persona, 4 modes (Mirror / Nudge / Challenge / Direct) | — | Needs scoping |
| `GET /summary` endpoint — currentFocus, themes, open threads, most important thing | — | Needs scoping |
| Context params on `/analyze` — pass `contextType` + `contextId` through to Claude prompt | — | Needs scoping |

### Product
| Work | Scope doc | Status | Blocked on |
|---|---|---|---|
| Logs tab — session list, taps open chat in continue mode | — | Needs scoping | Phase 1 |
| Account tab — rename + reorganize current You tab | — | Needs scoping | Light design system |

---

## Phase 3 — Intelligence layer

### Platform
| Work | Scope doc | Status |
|---|---|---|
| Persistent memory layer — stated patterns + open threads in `users` table, injected at session start | — | Needs scoping |
| Entry categorization — classify input into 6 types, return suggested type for lightweight confirmation | — | Needs scoping |

### Product
| Work | Scope doc | Status | Blocked on |
|---|---|---|---|
| Summary page — surfaces most important growth area, opens chat with theme as context | — | Needs scoping | chatProcessor, /summary endpoint, memory layer |
| Goals page — goal list, progress, linked logs, taps open chat with goal as context | — | Needs scoping | Context params on /analyze |

---

## Phase 4 — Progress layer

### Platform
| Work | Scope doc | Status |
|---|---|---|
| `GET /dashboard?period=` endpoint — goal progress, highlights, activity mapped to goals per time period | — | Needs scoping |
| Goals via chat — create and update goals from natural language input | — | Needs scoping |

### Product
| Work | Scope doc | Status | Blocked on |
|---|---|---|---|
| Dashboard page — goal progress visualization, time period toggle, highlights | — | Needs scoping | /dashboard endpoint |

---

## What's already built (v1 carry-forward)

These exist and carry into the new IA without a rebuild:

| What | Where | Notes |
|---|---|---|
| Goal management | Backend + DB | Goals, milestones, progress % — needs Goals page UI |
| Journal analysis | `journalProcessor.ts` | One-shot analysis — will be extended by chatProcessor |
| Action items | Backend + DB | Feeds into memory layer and Summary |
| Career themes | Backend + DB | Feeds into Summary |
| Chat sessions + messages | Backend + DB | Powers continue mode in chat UI |
| Onboarding | `app/onboarding/` | Unchanged |

---

## What gets retired

| What | Replaced by |
|---|---|
| `recording/index.tsx` | Chat UI (Mode 1 + 2) |
| `thread/[id].tsx` | Chat UI (Mode 3) |
| `(tabs)/today.tsx` | Logs + Summary pages |
| `(tabs)/threads.tsx` | Logs tab |
| `(tabs)/you.tsx` | Account tab |
| FAB component | Persistent input bar |
| Dark token values in `tailwind.config.js` | Light token values |
</content>

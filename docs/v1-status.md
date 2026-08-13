# V1 Status — What's Built vs. What's Spec'd

> Read this before planning what to build next. Updated as features ship.
> Last updated: 2026-08-13

## Current personal-alpha handoff

The code-only personal-alpha release is complete on `feature/local-first-coaching-platform` at
`850b3d6`. Device enrollment/authentication, local response feedback, explicit encrypted feedback
sharing/deletion, Railway packaging, production fail-closed checks, and the standalone iPhone
release profile are implemented. The next action is not more feature code: it is Baah's explicit
gate to create/configure/deploy Railway resources. Apple signing and standalone installation remain
a later separate gate. See `docs/features/personal-alpha-release.md` for exact commits, evidence,
and continuation instructions.

## Local-first platform build status

The feature branch now has the code-only platform foundation: portable contracts, a provider-neutral
stateless gateway, cost/privacy guardrails, SQLCipher local schema, repositories, governed memory,
bounded context, private save/deliberate submission, durable resume, encrypted export/restore,
deterministic redaction, optional device unlock, app-switcher shielding, and generic notifications.

Automated checks do not prove the native security boundary. SQLCipher, recovery promotion, Face ID,
app-switcher timing, file export/import, private-save network counts, and restore on a clean test
installation remain pending Baah's explicit managed-development-build/device gate. The feature is
not ready to Ship before that evidence exists.

There is no legacy migration system: Baah confirmed there is no backend data to preserve. Legacy
backend routes remain mounted for rollback during BUILD and have not been retired because recovery
evidence and route-retirement approval are still pending.

---

## What's Fully Wired and Working

The core loop is functional end-to-end:

| Feature | Status | Notes |
|---|---|---|
| Onboarding (3-step) | ✅ Built | Role, goals, coaching prefs → stored in `users` table |
| Voice recording | ✅ Built | `expo-av`, high quality, haptic feedback |
| Transcription | ✅ Built | OpenAI Whisper via `/api/v1/transcribe` |
| Journal entry creation | ✅ Built | POST `/api/v1/entries`, status: draft → processing → complete |
| Claude analysis | ✅ Built | `journalAgent.ts` → `journalProcessor.ts` prompt → structured JSON |
| Action item extraction | ✅ Built | Denormalised to `action_items` table, status tracking |
| Goal management | ✅ Built | Manual + AI-suggested goals, milestones, progress % |
| Trajectory snapshots | ✅ Built | POST `/api/v1/trajectory/generate`, requires 3+ entries |
| Performance review upload | ✅ Built | Text input → Claude extracts feedback + suggests goals |
| Daily notifications | ✅ Privacy-updated | Generic content-free local copy; no backend personalization call |
| Legacy JSON share | ✅ Existing | Not a full-fidelity recovery mechanism |
| Encrypted local recovery | 🧪 Code complete, device pending | Separate-passphrase SQLCipher database export, pending-voice guard, candidate validation, rollback-safe restore; audio files are not bundled |

---

## What Diverged From the Product Spec and Why

The product docs (artifacts #001–#005) describe a slightly different product than what was built. Neither is wrong — the build made pragmatic V1 decisions.

| Spec (artifacts #001–#005) | Reality (codebase) | Reason |
|---|---|---|
| Chat interface ("Conversation" surface) | One-shot voice analysis — no back-and-forth | Simpler first; chat is the next major build |
| CV Archive surface (artifact #004) | Action items list (partial approximation) | CV Moment not a first-class entity yet |
| Four-mode agent: Mirror / Nudge / Challenge / Direct | Single coaching analysis mode | Modes require chat + session memory; not yet implemented |
| Three memory layers: Immediate / Recent / Persistent | Single SQLite file, no layer distinction | V1 simplification from memory-model-003 |
| "Today View" (today's captures + open threads) | "Home" tab (stats card + recent entries) | Different framing, same intent |
| Bottom nav: Today / Capture / Chat / Archive / Goals | Home / Record / Trajectory / Profile | Built before IA (artifact #005) was finalised |
| Open Thread as first-class entity | `action_items` with `open` status | Approximated — good enough for V1 |

---

## Known Gaps (Not Divergence — Genuinely Missing)

These were never built, not re-scoped:

- **No multi-user account system** — the personal alpha now uses a one-time enrolled-device bearer credential, while the separate installation ID remains only for usage accounting/rate limiting. Public signup, login/logout, and account recovery remain out of scope.
- **No settings / edit profile screen** — profile is read-only after onboarding. Updates only via API.
- **No search or filter** — entries, goals, and action items cannot be filtered by date, theme, or status in the UI.
- **Tab icons are placeholders** — geometric shapes (○ ● △ □) in `(tabs)/_layout.tsx`. No real icons installed.
- **Notification times hard-coded** — 15:00 and 19:00 in `notifications.ts`. No user preference UI.
- **Mixed transitional surfaces** — the new chat/thread/career path is local-first, while some old Today/You/legacy screens and backend routes remain mounted until recovery evidence and the separate route-retirement gate.
- **No milestone detail UI** — milestones exist in the DB and API but are not browsable in the app.

---

## What to Build Next (Priority Order)

1. **Private Railway deployment gate** — after Baah approval, create the single-replica service and persistent volume, configure secrets/ceilings, build the container, and deploy.
2. **Standalone iPhone QA** — install the signed personal-alpha Release build, stop Metro/the Mac, and verify cellular coaching, credential recovery, feedback share/delete, and cost rejection.
3. **Native privacy and recovery QA** — finish destructive key-loss, raw SQLCipher-file, export/restore, app-lock/shield, and private-submission evidence.
4. **Explicit route-retirement decision** — only after recovery proof, decide whether to unmount legacy backend user-data routes.
5. **CV Archive as a first-class surface** — CV Moment entity, dedicated screen, copy-to-clipboard.
6. **Settings / edit profile** — basic UX hygiene. Needed before sharing with anyone else.
7. **Real tab icons** — install `lucide-react-native`, replace placeholders in `(tabs)/_layout.tsx`.
8. **NativeWind migration** — prerequisite for UI rebuild. Must be set up before redesigning any screen. Involves installing NativeWind, migrating `theme.ts` tokens to `tailwind.config.js`, and updating existing screens.

# Data Model

> Open this when touching anything data-related. The local schema below is authoritative for the
> new coaching path. The backend schema remains mounted only during the gated BUILD transition.

## Authoritative on-device database (schema version 1)

`mobile/src/db/schema.ts` is the executable source. The file is encrypted by SQLCipher with a
random 256-bit key stored as `WHEN_UNLOCKED_THIS_DEVICE_ONLY` in iOS Keychain. IDs and timestamps
are supplied by the client. Foreign keys, lifecycle checks, unique idempotency receipts, and FTS5
triggers are enforced locally.

| Table | Responsibility |
|---|---|
| `profile` | Role, company, career stage, goals text, coaching/accountability preferences |
| `conversations`, `messages` | Private/submitted/received conversation archive and lifecycle |
| `goals`, `milestones` | Lifecycle-aware career goals and milestones |
| `actions`, `action_transitions` | Open/completed actions plus source-bound explicit completion history |
| `evidence` | First-class evidence linked by message, goal, and action IDs |
| `memory_items`, `memory_sources` | Governed durable memory and exact message/evidence provenance |
| `memory_confirmations` | Payload-bound pending/confirmed/consumed user decisions |
| `coaching_requests` | Stable local text/voice request, retry, transcript, and response state |
| `audio_cleanup_queue` | Content-free, recoverable local audio deletion work |
| `usage_receipts` | Provider/model/token/audio/cost metadata without readable content |
| `mutation_receipts` | Idempotency fingerprint for local mutations |
| `migration_state` | Reserved schema-v1 authority metadata; no legacy import is shipped or required |
| `message_search`, `evidence_search` | External-content FTS5 indexes maintained by triggers |

Readable values in these tables are never replicated into the gateway database. Zustand is view
state, not durable authority.

### Manual encrypted recovery

An exported SQLCipher database contains the complete local schema plus an encrypted
`taisa_archive_manifest` with format/schema versions, per-table counts, and a SHA-256 content
fingerprint. The manifest exists inside the encrypted backup only. Restore validates the selected
archive and a device-key candidate before promotion. A rollback copy and marker preserve the prior
active archive across recoverable failures or interruption.

The archive is database-only. It preserves completed transcripts but does not bundle the files
referenced by `coaching_requests.audio_uri` or `audio_cleanup_queue.audio_uri`. Export therefore
fails closed while any nonterminal coaching request still references audio; pending voice work must
be finished or abandoned before a portable backup can be created.

This is manual recovery, not sync. Losing the phone before moving an export outside the app,
forgetting the separate passphrase, uninstalling without a backup, or losing both phone and backup
can permanently lose the archive. Taisa has no recovery key and no readable cloud copy.

---

## Legacy backend database (still mounted, pending retirement gate)

The nine tables below describe the original server-authoritative journal product. No migration
route exists because there is no backend data Baah needs to preserve. Do not add new local-first
coaching writes here. Route unmounting is deferred until physical-device recovery evidence and
explicit route-retirement approval.

## The 9 legacy tables

### `users`
Career profile. One row per device (v1 has no auth — `id` is the device UUID).

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | Device UUID |
| `current_role`, `current_company`, `industry` | TEXT | Career context from onboarding |
| `years_of_experience` | INTEGER | |
| `career_stage` | TEXT | `early` / `mid` / `senior` / `executive` / `founder` |
| `current_focus_area` | TEXT | Current sprint/focus from onboarding |
| `short_term_goal`, `long_term_goal` | TEXT | Free text from onboarding |
| `coaching_style` | TEXT | `direct` / `supportive` / `socratic` / `structured` |
| `accountability_level` | TEXT | `gentle` / `moderate` / `intense` |
| `reminder_times` | TEXT | JSON array, default `["15:00","19:00"]` |
| `dominant_themes` | TEXT | JSON array, updated by trajectory agent |
| `growth_trajectory` | TEXT | `rising` / `steady` / `plateaued` / `transitioning` |
| `open_action_item_count`, `total_entry_count` | INTEGER | Denormalised counters |
| `last_entry_at` | TEXT | ISO timestamp of most recent entry |

---

### `journal_entries`
The raw input — voice or text — before and after analysis.

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `user_id` | TEXT FK → users | |
| `recorded_at` | TEXT | When the user recorded the entry (may differ from `created_at`) |
| `input_type` | TEXT | `voice` / `text` |
| `raw_transcript` | TEXT | From Whisper or direct input |
| `edited_transcript` | TEXT | User-edited version (optional) |
| `audio_duration_seconds` | REAL | |
| `audio_file_ref` | TEXT | Reference to stored audio file (optional) |
| `status` | TEXT | `draft` → `transcribing` → `processing` → `complete` / `error` |
| `analysis_id` | TEXT | FK → entry_analyses (set after analysis) |

---

### `entry_analyses`
The Claude output for a journal entry. Stored as JSON columns.

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `entry_id` | TEXT FK → journal_entries | |
| `model_version` | TEXT | Claude model used (e.g. `claude-3-5-sonnet-20241022`) |
| `summary` | TEXT | 1–2 sentence summary |
| `sentiment` | TEXT | `very_positive` / `positive` / `neutral` / `challenging` / `difficult` |
| `energy_level` | INTEGER | 1–5 |
| `momentum_signal` | TEXT | `accelerating` / `steady` / `stalling` / `recovering` |
| `wins` | TEXT | JSON array of `{ title, description, impact, category }` |
| `challenges` | TEXT | JSON array of `{ title, description, category, resolution }` |
| `decisions` | TEXT | JSON array of `{ title, description, decisionMade, context }` |
| `action_items` | TEXT | JSON array (also denormalised to `action_items` table) |
| `themes` | TEXT | JSON array of `{ label, weight }` |
| `coach_note` | TEXT | The agent's main observation — shown prominently in UI |
| `growth_areas` | TEXT | JSON array of strings — areas for development the agent identified |
| `goal_assessments` | TEXT | JSON array of `{ goalId, evidence, progressDelta, milestonesAchieved }` |
| `pattern_flags` | TEXT | JSON array of `{ patternType, description, relatedEntryIds }` — recurring patterns the agent noticed |
| `accountability_callouts` | TEXT | JSON array of strings — follow-up items from prior sessions |

---

### `action_items`
Denormalised from `entry_analyses` for efficient querying across entries.

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `user_id` | TEXT FK → users | |
| `source_entry_id` | TEXT FK → journal_entries | |
| `title` | TEXT | The action item text |
| `priority` | TEXT | `low` / `medium` / `high` |
| `status` | TEXT | `open` / `completed` / `dropped` |
| `due_context` | TEXT | Optional — "by end of sprint", "this week" |

---

### `goals`
Career goals. Created manually or suggested by Claude after a performance review.

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `user_id` | TEXT FK → users | |
| `title` | TEXT | |
| `description` | TEXT | |
| `source_review_id` | TEXT FK → performance_reviews | NULL if manually created |
| `suggested_by_ai` | INTEGER | 0 / 1 |
| `priority` | TEXT | `low` / `medium` / `high` |
| `status` | TEXT | `active` / `achieved` / `dropped` |
| `progress_percent` | INTEGER | 0–100, updated by journal analysis |
| `related_themes` | TEXT | JSON array of theme labels |
| `target_date` | TEXT | Optional ISO date |

---

### `milestones`
Sub-tasks for a goal. Not yet surfaced in the mobile UI.

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `goal_id` | TEXT FK → goals | |
| `title` | TEXT | |
| `status` | TEXT | `pending` / `complete` |
| `evidence_entry_ids` | TEXT | JSON array of entry IDs that count as evidence |

---

### `performance_reviews`
Uploaded review text + Claude's structured extraction.

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `user_id` | TEXT FK → users | |
| `reviewer_context` | TEXT | Who gave the review, what role |
| `raw_text` | TEXT | The pasted review |
| `extracted_feedback` | TEXT | JSON: `{ strengths, growthAreas, concerns, themes, coachSummary, alignmentWithJournal }` |
| `suggested_goals` | TEXT | JSON array of goal objects with milestones |

---

### `career_themes`
Aggregate frequency of themes across all journal entries.

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `user_id` | TEXT FK → users | |
| `label` | TEXT | e.g. "stakeholder alignment", "design strategy" |
| `count` | INTEGER | Incremented each time theme appears in an analysis |
| `trend` | TEXT | `increasing` / `stable` / `decreasing` |
| `first_seen_at`, `last_seen_at` | TEXT | ISO timestamps |
| `UNIQUE(user_id, label)` | | One row per theme per user |

---

### `trajectory_snapshots`
Periodic Claude-generated career narrative. Requires 3+ entries.

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `user_id` | TEXT FK → users | |
| `generated_at` | TEXT | ISO timestamp |
| `period_start`, `period_end` | TEXT | ISO dates the snapshot covers |
| `narrative_summary` | TEXT | The career arc story |
| `key_themes` | TEXT | JSON array of `ThemeTrend` objects |
| `momentum_history` | TEXT | JSON array of `{ entryId, recordedAt, signal, sentiment, energyLevel }` |
| `win_count`, `challenge_count`, `resolved_challenge_count` | INTEGER | Aggregate counters for the period |
| `growth_observations` | TEXT | JSON array of strings — specific growth signals |
| `suggested_focus_areas` | TEXT | JSON array of strings |
| `goal_progress_summaries` | TEXT | JSON array of `{ goalId, goalTitle, progressPercent, observation, evidenceCount }` |

---

## Legacy memory-model mapping

The product spec (artifact #003) defines six memory entities. Here's how they map to the actual DB:

| Product entity | DB table(s) | Status | Gap |
|---|---|---|---|
| Goal | `goals` | ✅ Direct match | — |
| Log Entry | `journal_entries` | ✅ Voice/text, richer than spec'd | — |
| CV Moment | `action_items` (high priority, open) | ⚠️ Approximated | No dedicated CV archive; no draft bullet generation |
| Insight | `entry_analyses.coach_note` | ⚠️ Partial | Per-session only; not aggregated across sessions |
| Pattern | `career_themes` + `trajectory_snapshots` | ⚠️ Partial | Themes tracked, but not surfaced as named patterns |
| Open Thread | `action_items` (open status) | ⚠️ Approximated | Not a first-class entity; no explicit "thread" concept |

**The three memory layers** (Immediate / Recent / Persistent) from artifact #003 are **not implemented** as distinct DB structures. All data lives in the same SQLite file. This is the primary architectural gap to close when building the chat interface. See `docs/agent-persona.md`.

---

## How legacy context gets injected into Claude

The legacy journal agent loads the following. The new coaching gateway never performs these reads;
its context arrives as a bounded, validated mobile request.

```
entry           → the journal_entries row being analysed
profile         → user role, company, coaching style, goals text, current_focus_area
open_items      → action_items with status = 'open' (most recent first, LIMIT 10)
themes          → career_themes ordered by count DESC (LIMIT 20)
active_goals    → goals with status = 'active', including milestones (no LIMIT — all active goals loaded)
```

This context is formatted into the prompt by the prompt builder functions in `backend/src/prompts/system/journalProcessor.ts`. The agent does not load prior session transcripts or analyses — only the aggregated artifacts (themes, goals, open items).

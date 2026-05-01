# Taisa MVP UI Design Spec

**Date:** 2026-05-01
**Status:** Approved
**Author:** Baah + Claude
**Topic:** Full mobile UI redesign — navigation, all screens, recording flow, and content surfacing logic

> This spec supersedes the UI/Track A sections of `2026-04-17-taisa-mvp-design.md`. The chat backend from Track B (chat_sessions, chat_messages, chatAgent.ts, 3 chat routes) is already shipped and still applies — this spec defines how the UI presents that system.

---

## Core Product Reframe

Taisa is not a journal with AI attached. It is an ongoing coaching relationship. Everything — voice logs, text exchanges, follow-up conversations — is part of a continuous conversation. There is no distinction between "a log" and "a chat." Both are threads. Both automatically get a Taisa response.

The old model (Logs tab + Chat tab as separate surfaces) is gone. The new model:

- **Today** — Taisa's coaching surface. What she wants to surface to you right now.
- **Threads** — The full conversation history. Every session, voice entry, and exchange.
- **You** — Taisa's read on you. Your career context, recurring themes, open loops.

---

## Navigation

Three tabs + a global floating action button (FAB).

```
Tab bar (bottom, persistent):
  ◈  Today    ◎  Threads    ○  You

FAB (floating above tab bar, visible from all tabs):
  +  Opens recording overlay
```

The FAB is the primary entry point for all new sessions. It is always visible regardless of which tab is active.

---

## The Thread Model

Every interaction — voice or text — is a **thread**. A thread has:

- A title (auto-generated from content after transcription/analysis)
- A sequence of messages alternating between the user and Taisa
- A status: `live` (active in last session) or closed (past)
- A voice indicator when the user's entry was voice (waveform glyph + duration)

When a user records a voice entry, the thread is created with:
1. The user's transcription as the first message
2. Taisa's analysis reply as the second message
3. An open input for the user to continue

**Voice entries** are displayed differently in thread lists: instead of a text snippet, they show a waveform glyph (〜〜〜) and the audio duration.

This maps to the existing backend tables:
- Thread = `chat_session` row
- Messages = `chat_messages` rows (role: user / assistant)

**Backend gap to close:** The current voice pipeline writes to `journal_entries` (with analysis stored as JSON). It does not currently create a `chat_session`. To make voice entries first-class threads, after transcription + analysis, the backend must:
1. Create a `chat_session` row (with `entry_id` pointing to the journal_entry for audit, nullable)
2. Insert the transcription as a `chat_message` with `role: 'user'`
3. Insert Taisa's analysis reply as a `chat_message` with `role: 'assistant'`

The journal_entry record can be retained for backward compatibility. The thread view reads from `chat_messages` only. This bridge is a backend task, not a UI task — but the UI cannot work without it.

---

## Screen 1 — Today Tab

### Purpose
Taisa's active coaching surface. The first screen the user sees each day. Not a feed. One focused thing from Taisa, with recent context below.

### Two states

**Daily state (Tuesday through Sunday — or any day without a gap)**

```
Header: "Today" + date

[ Taisa card — one card, priority-selected ]

RECENT ─────────────────────
[ Thread row ]
[ Thread row ]
[ Thread row ]

                    [ + FAB ]
```

**Digest state (Monday, or return after 2+ day gap)**

The daily Taisa card is replaced by a weekly digest card. The digest is also triggered by Taisa's own judgment when she has accumulated enough patterns to surface — it is not purely calendar-based.

```
Header: "Today" + date

[ Digest card — "Taisa's week in review" ]
  ● Pattern: Stakeholder friction — showing up every session → tap to discuss
  ● Win: Design system ship — CV moment to frame → tap to frame
  ● Open: PM follow-up — still open → mark done or continue

LAST WEEK ──────────────────
[ Thread row ]

                    [ + FAB ]
```

### Taisa card

The card leading the daily view. One of six types (see Content Types below), selected by priority logic. Always has:
- An eyebrow label (e.g., "🎯 Prep — tomorrow" or "🔁 Pattern")
- A body — Taisa's voice, first person, direct. Not a summary header.
- A CTA tap target (e.g., "Let's prepare →" or "Tap to discuss →")
- Purple left border (2px, accent color)

### Content types (6)

These are the categories of things Taisa can surface. They are the engine of her intelligence — not a checklist to fill every day.

| Type | Label | Trigger |
|---|---|---|
| Patterns (🔁) | "Pattern" | Same theme in 3+ sessions |
| Commitments (✋) | "Follow-up" | User said they'd do something; not yet marked done |
| CV Moments (⭐) | "Capture" | Significant achievement mentioned, not yet framed |
| Reframes (💡) | "Reframe" | User framed something negatively; Taisa has a different read |
| Momentum (📈) | "Momentum" | Streak of positive/negative sessions worth naming |
| Prep (🎯) | "Prep" | User mentioned an upcoming event/deadline within ~3 days |

### Priority logic (what gets shown)

A single priority engine orders available content. The card shown is always the highest-priority available item.

Priority order:
1. **Time-sensitive prep** — upcoming event within 24–72 hours → always floats to top
2. **Urgent commitments** — overdue follow-up from 7+ days ago
3. **Strong patterns** — same theme in 5+ sessions (escalated)
4. **CV moments** — significant win in last 48 hours
5. **Soft patterns** — same theme in 3–4 sessions
6. **Reframes** — Taisa has a different read on something recent
7. **Momentum** — streak signals (positive or negative)
8. **Standard commitments** — open follow-up from 3–7 days ago

If nothing meets the threshold for any category, Today shows only the recent threads (no card). This is valid — not every day needs Taisa to surface something.

### Recent threads section

Below the Taisa card: the 2–3 most recent threads, same format as in the Threads tab (see below). Tapping any thread opens it directly.

---

## Screen 2 — Threads Tab

### Purpose
The full conversation history. Every thread, searchable. The archive.

### Layout

```
Header: "Threads"

[ Search bar — "Search conversations..." ]

[ Thread row ] ← LIVE badge if active
[ Thread row ]
[ Thread row ]
[ Thread row ]
...

                    [ + FAB ]
```

### Thread row format

```
[LIVE]  (if active — purple pill badge)
Title                                    Date
You: "Last thing the user said..."
Taisa: "Last thing Taisa said..."        (purple text)
```

Voice entries replace the user text excerpt with:
```
〜〜〜  1:12 voice
```

### States
- **LIVE** — the most recent message in this thread was sent today. Purple dot + "LIVE" badge.
- **Closed** — no messages today. Grey dot + relative date ("3 days ago", "Mon")

### Search
Full-text search across thread titles and message content. Searches both transcribed voice content and text. No pagination in v1 — load all threads.

---

## Screen 3 — Recording Flow

The FAB is the entry point for all new sessions.

### Step 1 — Recording overlay

Opens from any tab as a modal overlay (slides up from bottom). The tab bar remains visible beneath.

```
────────────────────────────
                             (handle)
  RECORDING

  〜 〜 〜 〜 〜              (animated waveform)

         🎤                  (pulse animation)

       0:43                  (timer)
    Tap to stop

  [ Done ]

  Starting new thread  ·  or  add to existing →
─────────────────────────────
[ tab bar ]
```

- Default: starts a new thread
- "Done" stops recording and triggers transcription + analysis pipeline
- "Add to existing →" — deferred to v2. In v1, all recordings start new threads.

### Step 2 — Result screen (= the thread)

After recording, the result screen opens. This IS the thread — not a separate view. The thread title is auto-generated from the content. Taisa's reply appears below the transcription.

```
Thread title (auto-generated)

[ 🎤 Voice · 1:12 ]
"Finally got it across the line after 6 weeks. The 
stakeholder sign-off came through this morning..."

✦ Wins ─────────────────────
● Shipped design system v1 after 6 weeks
● Immediate eng adoption — no friction

⚡ Action ───────────────────
● Frame this for your CV this week

┌──────────────────────────────┐
│ Taisa                        │
│ "Six weeks of quiet work...  │
│  Want to frame it properly   │
│  while the detail is fresh?" │
└──────────────────────────────┘

[ Reply...                  🎤 ]
```

The input at the bottom is ready for voice or text continuation. The user does not need to go back to the thread list first. The result screen and the thread are the same screen.

**Loading states:**
- While transcribing + analysing: shimmer/skeleton on the wins, actions, and Taisa reply sections
- Error: retry button appears below the failed section

**No separate entry detail screen.** This design eliminates it. The result screen IS the thread.

---

## Screen 4 — You Tab

### Purpose
Taisa's read on the user. A mirror, not a settings panel. The primary value is seeing what Taisa has learned — current focus, recurring themes, open loops.

### Layout

```
[ Avatar initials ]  Name
                     Role  ·  N sessions

── TAISA'S READ ON YOU ─────────
[ Current focus card ]
  Current focus
  "Navigating stakeholder friction while shipping..."

[ Recurring themes card ]
  Recurring themes
  [Stakeholder friction] [Principal-level work] [Visibility gap]

[ Open loops card ]
  Open loops
  "PM follow-up · Leadership principles · Director 1:1"

── CAREER CONTEXT ───────────────
[ Goals row → ]
  🎯  Goals
      Staff promotion in ~12 months

[ Context row → ]
  🏢  Role & company
      Senior Designer, TechCo

── SETTINGS ─────────────────────
[ Weekly digest toggle ]
[ Export my data → ]
```

### Taisa's read on you section

This section is read-only — populated by Taisa's analysis from all previous sessions. The user does not manually edit these fields.

**Data source:** A new backend endpoint `GET /api/v1/today/you` synthesises these fields by running a Claude call across the user's recent journal analysis JSON. It returns:
- `currentFocus: string` — one-sentence synthesis of current work preoccupation
- `themes: string[]` — recurring theme tags from pattern detection
- `openLoops: string` — comma-separated unresolved commitments phrase

This endpoint is called once on You tab load and cached for the session. It reads from existing `journal_entries.analysis` JSON — no new DB tables required.

- **Current focus**: One sentence. What is occupying the user's work life right now.
- **Recurring themes**: Tags. In v1 display only — no tap action. (Tap to filter threads is v2.)
- **Open loops**: Comma-separated unresolved commitments from across sessions.

### Career context section

This section IS user-editable. Tapping either row opens an edit sheet. Data here is static context injected into every chat session.

- **Goals**: Free-text. What are you working toward in your career?
- **Role & company**: Role title + company name/type

### Settings section

Minimal. Not the focus of this tab.

- **Weekly digest** — toggle on/off (default: on). Controls Taisa's proactive periodic digest. The gap-triggered digest (return after 2+ days) always shows regardless of this toggle.
- **Export my data** — tap → triggers a JSON export of all threads and analysis. No confirmation in v1; export goes to share sheet.

---

## Design Tokens

From `mobile/src/constants/theme.ts` — all screens use these tokens via NativeWind:

| Token | Value | Usage |
|---|---|---|
| `background` | `#0A0A0F` | Screen backgrounds |
| `surface` | `#13131A` | Cards, rows |
| `surface-elevated` | `#1C1C27` | Tab bar, borders |
| `accent` | `#7C6FFF` | Purple — Taisa's voice, active states, CTAs |
| `text-primary` | `#FFFFFF` | Headlines, thread titles |
| `text-secondary` | `#AAAAAA` | Body text, descriptions |
| `text-muted` | `#555555` | Labels, timestamps, inactive tabs |
| `success` | `#4CAF7D` | Win dots |
| `warning` | `#F5A623` | Action/open items |

No `StyleSheet.create()` in any new component. NativeWind only.

---

## Component Inventory

New components to build (all in `mobile/src/components/`):

| Component | Purpose |
|---|---|
| `TaisaCard` | The coaching surface card on Today — eyebrow, body, CTA, purple border |
| `DigestCard` | Monday/gap digest — session count, pattern/win/open items list |
| `ThreadRow` | Reusable thread preview row — title, date, user/Taisa last message snippets, LIVE badge, voice indicator |
| `RecordingOverlay` | Modal overlay — waveform animation, timer, done button |
| `TaisaReplyCard` | Taisa's reply within a thread — purple left border, "Taisa" label, body text |
| `ThreadView` | Full thread screen — list of messages (user + Taisa), voice entry formatting, input bar |
| `ThemeTag` | Recurring theme tag on You tab — purple background, small text |
| `SearchBar` | Thread search input on Threads tab |
| `FAB` | Global floating action button — triggers recording overlay |

---

## Screen Routing

Using Expo Router (existing setup). The new route structure:

```
app/
  (tabs)/
    _layout.tsx         ← Tab bar config: Today | Threads | You
    today.tsx           ← Today tab
    threads.tsx         ← Threads tab (list)
    you.tsx             ← You tab
  thread/
    [id].tsx            ← Full thread view (tapping any row OR after recording)
  recording/
    index.tsx           ← Recording overlay (modal)
  onboarding/
    index.tsx           ← Existing onboarding (rebuild in NativeWind)
```

`recording/index.tsx` is a modal (transparent background, slides up). After recording completes, it navigates to `thread/[newSessionId]` — there is no separate result route. The thread view handles both the post-recording initial state and reopened threads identically.

---

## What Changes vs April 17 Spec

| April 17 | This spec |
|---|---|
| Logs tab | Replaced by Threads tab |
| Chat tab | Eliminated — chat is part of every thread |
| Profile tab | Replaced by You tab |
| Entry detail (read-only analysis + chat below) | Eliminated — result screen IS the thread |
| New thread = requires Chat tab | New thread = FAB from any tab |
| Journal analysis separate from chat | Voice recording creates a thread; analysis = Taisa's first reply |

The chat backend (chat_sessions, chat_messages, chatAgent.ts, 3 routes) is unchanged and still powers all conversation. The UI layer is entirely new.

---

## What's Deferred

- Tapping a theme tag to filter threads (You tab — v2)
- Four interaction modes (Mirror / Nudge / Challenge / Direct)
- Session summaries
- CV Archive as a dedicated screen
- Persistent memory layer (patterns/threads as structured DB fields)
- Prior session context as narrative in system prompt
- Real Lucide tab icons (currently geometric placeholders)
- Notification preferences UI
- Offline support / caching
- Settings / edit profile as a separate screen (edit is inline in You tab for now)

---

## Build Order

### Backend bridge (must precede UI)

1. **Voice → thread bridge** — after transcription + analysis, create a `chat_session` + two `chat_messages` (user transcription, assistant analysis). Update `backend/src/routes/journal.ts` or `journalAgent.ts`.
2. **`GET /api/v1/today/card`** — returns the priority-selected Taisa card content (type, eyebrow, body, CTA). Runs the priority logic against the user's data.
3. **`GET /api/v1/today/digest`** — returns digest content (session count, patterns, wins, open items) when gap ≥ 2 days or periodic judgment applies.
4. **`GET /api/v1/today/you`** — returns `{ currentFocus, themes, openLoops }` synthesised by Claude from recent analysis.

### UI (Track A)

Build order for UI:

1. **Tab scaffold** — update `(tabs)/_layout.tsx` to 3 tabs (Today, Threads, You) with correct labels
2. **Shared components** — `ThreadRow`, `FAB`, `TaisaReplyCard`, `SearchBar`
3. **Threads tab** — thread list, search, LIVE badge, voice indicators
4. **Thread view** — `thread/[id].tsx` — full message history, shimmer on initial load, input bar
5. **Recording overlay** — `RecordingOverlay` component + `recording/index.tsx` modal → navigates to `thread/[id]` on complete
6. **Today tab** — daily state (TaisaCard + recent ThreadRows), digest state (DigestCard + thread rows)
7. **TaisaCard + DigestCard** — wired to `/api/v1/today/card` and `/api/v1/today/digest`
8. **You tab** — Taisa's read section (from `/api/v1/today/you`), career context (editable), settings strip
9. **Onboarding** — rebuild existing screens in NativeWind

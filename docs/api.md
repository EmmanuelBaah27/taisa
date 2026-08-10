# API Reference

> Reference when adding or modifying an endpoint. All routes are prefixed `/api/v1`.
> Auth: pass `x-user-id` header on every request. Set automatically by `mobile/src/services/api.ts` via Axios interceptor.
> The only exception is `POST /api/v1/profile/init`, which accepts `deviceId` in the request body instead.

## Current local-first boundary

The mobile client is authoritative for readable user data. Only two content-processing endpoint
families belong to the new path:

| Route | Status | Persistence boundary |
|---|---|---|
| `POST /api/v1/coaching/respond` | Current stateless coaching path | Validates bounded supplied context, makes one configured provider call, returns structured coaching/proposals; stores no readable user content |
| `POST /api/v1/transcribe` | Current deliberate voice path | Deletes temporary audio in `finally`; stores only content-free usage/cost metadata |
| `GET /health` | Current operational health | No user data |

The gateway still uses `x-user-id` as a device-keyed rate-limit identifier, not as authentication.
No migration/export endpoint exists. Baah has no backend archive to migrate, and Task 7 was removed.

Profile, entries, analyze, reviews, goals, action-items, trajectory, notifications, chat, and today
routes remain mounted as legacy rollback compatibility during BUILD. They must not receive new
local-first coaching writes. Removal is separately gated on verified encrypted device recovery and
Baah's explicit cutover approval; `backend/src/index.ts` intentionally remains unchanged in this
slice.

### `POST /api/v1/coaching/respond`

Accepts one `CoachingRequest` from `@taisa/shared`, with a 4,000-character input, at most 20 recent
messages, 50 memory items, and 8 evidence excerpts. Runtime validation is strict. The response is a
request-bound `CoachingResponse` containing concise coaching text, one stance, governed proposed
deltas, and a content-free usage receipt. Invalid structured output is recoverable and never causes
an automatic second paid call.

The gateway does not fetch profile, history, goals, actions, evidence, or memory. It does not write
the request, response, transcript, prompt, or coaching text. Daily/monthly/per-request cost ceilings
fail closed before the configured OpenAI or Anthropic adapter is called.

---

## Legacy route overview (mounted pending retirement)

| Route group | Prefix | Claude agent |
|---|---|---|
| Profile | `/api/v1/profile` | none |
| Entries | `/api/v1/entries` | none |
| Transcribe | `/api/v1/transcribe` | none (OpenAI Whisper) |
| Analyze | `/api/v1/analyze` | `journalAgent` (`analyzeEntry`) |
| Reviews | `/api/v1/reviews` | `performanceReviewAgent` (`analyzePerformanceReview`) |
| Goals | `/api/v1/goals` | none |
| Action Items | `/api/v1/action-items` | none |
| Trajectory | `/api/v1/trajectory` | `trajectoryAnalyst` (direct `callClaudeJson`) |
| Notifications | `/api/v1/notifications` | `trajectoryAnalyst` check-in prompts (direct `callClaude`) |
| Chat | `/api/v1/chat` | legacy backend-readable chat |
| Today | `/api/v1/today` | legacy backend-readable summaries |

Everything below, except the current transcription section, documents the legacy API while it
remains mounted. It is retained so rollback behavior is explicit rather than silently stale.

---

## Profile

### `POST /api/v1/profile/init`

Create or retrieve a user profile. Uses `deviceId` as the user ID (MVP shortcut — no separate auth).

**Request body**
```json
{
  "deviceId": "string (required)",
  "currentRole": "string",
  "currentCompany": "string | null",
  "industry": "string",
  "yearsOfExperience": "number",
  "careerStage": "string (default: 'mid')",
  "shortTermGoal": "string",
  "longTermGoal": "string",
  "currentFocusArea": "string",
  "coachingStyle": "string (default: 'direct')",
  "accountabilityLevel": "string (default: 'moderate')",
  "reminderTimes": ["15:00", "19:00"]
}
```

**Response** `201` (new user) or `200` (existing user)
```json
{
  "success": true,
  "isNew": true,
  "data": { /* CareerProfile — see shape below */ }
}
```

---

### `GET /api/v1/profile`

Retrieve the current user's profile.

**Response** `200`
```json
{
  "success": true,
  "data": {
    "id": "string",
    "userId": "string",
    "createdAt": "ISO8601",
    "updatedAt": "ISO8601",
    "currentRole": "string",
    "currentCompany": "string | null",
    "industry": "string",
    "yearsOfExperience": "number",
    "careerStage": "string",
    "shortTermGoal": "string",
    "longTermGoal": "string",
    "currentFocusArea": "string",
    "coachingStyle": "string",
    "accountabilityLevel": "string",
    "reminderTimes": ["string"],
    "dominantThemes": ["string"],
    "growthTrajectory": "string",
    "openActionItemCount": "number",
    "totalEntryCount": "number",
    "lastEntryAt": "ISO8601 | null"
  }
}
```

---

### `PUT /api/v1/profile`

Update any subset of profile fields. All fields are optional; unset fields are left unchanged (`COALESCE` update).

**Request body** — any subset of the `CareerProfile` writable fields:
```json
{
  "currentRole": "string",
  "currentCompany": "string",
  "industry": "string",
  "yearsOfExperience": "number",
  "careerStage": "string",
  "shortTermGoal": "string",
  "longTermGoal": "string",
  "currentFocusArea": "string",
  "coachingStyle": "string",
  "accountabilityLevel": "string",
  "reminderTimes": ["string"]
}
```

**Response** `200` — same shape as `GET /api/v1/profile`.

---

## Entries

Journal entries are the core data unit. An entry starts as `draft`, moves to `processing` during AI analysis, and ends up `analyzed` or `error`.

### `GET /api/v1/entries`

List journal entries, newest first.

**Query params**
| Param | Type | Default | Notes |
|---|---|---|---|
| `limit` | number | `20` | Page size |
| `offset` | number | `0` | Pagination offset |
| `since` | ISO8601 | — | Filter by `recorded_at >= since` |

**Response** `200`
```json
{
  "success": true,
  "data": {
    "items": [{ /* JournalEntry */ }],
    "total": "number",
    "limit": "number",
    "offset": "number",
    "hasMore": "boolean"
  }
}
```

`JournalEntry` shape:
```json
{
  "id": "string",
  "userId": "string",
  "createdAt": "ISO8601",
  "updatedAt": "ISO8601",
  "recordedAt": "ISO8601",
  "inputType": "string ('voice' | 'text')",
  "rawTranscript": "string",
  "editedTranscript": "string | null",
  "audioDurationSeconds": "number | null",
  "audioFileRef": "string | null",
  "status": "string ('draft' | 'processing' | 'analyzed' | 'error')",
  "analysisId": "string | null"
}
```

---

### `POST /api/v1/entries`

Create a new journal entry. Status is set to `draft` automatically. Also increments `users.total_entry_count`.

**Request body**
```json
{
  "rawTranscript": "string (required)",
  "inputType": "string (default: 'voice')",
  "editedTranscript": "string | null",
  "audioDurationSeconds": "number | null",
  "recordedAt": "ISO8601 (default: now)"
}
```

**Response** `201`
```json
{
  "success": true,
  "data": { /* JournalEntry */ }
}
```

---

### `GET /api/v1/entries/:id`

Fetch a single entry and its associated analysis (if available).

**Response** `200`
```json
{
  "success": true,
  "data": {
    "entry": { /* JournalEntry */ },
    "analysis": { /* EntryAnalysis | null — see shape below */ }
  }
}
```

`EntryAnalysis` shape (populated after `/api/v1/analyze/:entryId` runs):
```json
{
  "id": "string",
  "entryId": "string",
  "createdAt": "ISO8601",
  "modelVersion": "string",
  "summary": "string",
  "sentiment": "string",
  "energyLevel": "number",
  "wins": ["string"],
  "challenges": ["string"],
  "decisions": ["string"],
  "actionItems": [{ /* ActionItem */ }],
  "themes": ["string"],
  "coachNote": "string",
  "growthAreas": ["string"],
  "momentumSignal": "string",
  "patternFlags": ["string"],
  "accountabilityCallouts": ["string"],
  "goalAssessments": [{ /* GoalAssessment */ }]
}
```

---

### `PUT /api/v1/entries/:id`

Update an entry's edited transcript or status.

**Request body**
```json
{
  "editedTranscript": "string",
  "status": "string"
}
```

**Response** `200`
```json
{
  "success": true,
  "data": { /* JournalEntry */ }
}
```

---

## Transcribe

### `POST /api/v1/transcribe`

Transcribe an audio file using the configured OpenAI transcription model. Accepts `multipart/form-data`. The temporary file is deleted before the success or failure response completes. The server measures the uploaded audio and uses that measured duration for duration and cost checks before OpenAI is invoked.

**Request** — `multipart/form-data`
| Field | Type | Notes |
|---|---|---|
| `audio` | file | Required. A parseable format accepted by the configured transcription provider, within `TAISA_TRANSCRIPTION_MAX_UPLOAD_BYTES` |
| `durationSeconds` | string/number | Optional display metadata. A material mismatch with measured duration is rejected; it is never used for cost or ceiling decisions |

**Response** `200`
```json
{
  "success": true,
  "data": {
    "transcript": "string",
    "durationSeconds": "number",
    "usage": {
      "provider": "openai",
      "model": "string",
      "audioSeconds": "number",
      "estimatedCostUsd": "number"
    }
  }
}
```

Required runtime settings are `TAISA_TRANSCRIPTION_MODEL`, `TAISA_TRANSCRIPTION_MAX_DURATION_SECONDS`, `TAISA_TRANSCRIPTION_MAX_UPLOAD_BYTES`, `TAISA_TRANSCRIPTION_PRICE_USD_PER_MINUTE`, `TAISA_AI_COST_CEILING_PER_REQUEST_USD`, `TAISA_AI_COST_CEILING_DAILY_USD`, and `TAISA_AI_COST_CEILING_MONTHLY_USD`. Missing or invalid settings fail closed with `503 TRANSCRIPTION_CONFIG_ERROR`; upload or duration overflow returns `413`; a caller-duration mismatch returns `422 AUDIO_DURATION_MISMATCH`; a cost ceiling returns `429 COST_LIMIT_EXCEEDED`. Only content-free usage receipts, timestamps, and reservations are stored at `TAISA_USAGE_LEDGER_PATH`; transcripts, prompts, responses, and uploaded audio are never stored there.

The SQLite usage ledger provides transactional reservations and restart recovery for the single-instance MVP. Horizontal replicas require a shared accounting store so reservations remain globally atomic. Coaching providers additionally require their `TAISA_<PROVIDER>_MODEL`, input/output price, and `MAX_OUTPUT_TOKENS` settings; the explicit output cap is included in the conservative pre-call reservation.

---

## Analyze

Runs the `journalAgent` Claude pipeline against an existing entry. The entry's `status` transitions to `processing` immediately, then `analyzed` on success or `error` on failure.

### `POST /api/v1/analyze/:entryId`

Trigger AI analysis for an entry. Calls `analyzeEntry(entryId, userId)` from `backend/src/services/claude/journalAgent.ts`.

**Response** `200`
```json
{
  "success": true,
  "data": { /* EntryAnalysis (same shape as GET /entries/:id analysis field) */ }
}
```

---

### `GET /api/v1/analyze/:entryId`

Retrieve a previously generated analysis for an entry (reads from DB, no Claude call).

**Response** `200`
```json
{
  "success": true,
  "data": { /* EntryAnalysis */ }
}
```

Returns `404` if the entry has no linked `analysis_id`.

---

## Reviews

Performance review analysis. Accepts raw review text, runs the `performanceReviewAgent`, and persists the structured result.

### `POST /api/v1/reviews`

Submit a performance review for AI analysis. Calls `analyzePerformanceReview` from `backend/src/services/claude/performanceReviewAgent.ts`. Also creates goal records from `suggestedGoals`.

**Request body**
```json
{
  "rawText": "string (required)",
  "reviewerContext": "string (default: 'Performance review')"
}
```

**Response** `201`
```json
{
  "success": true,
  "data": {
    "id": "string",
    "userId": "string",
    "createdAt": "ISO8601",
    "reviewerContext": "string",
    "rawText": "string",
    "extractedFeedback": { /* structured feedback object from Claude */ },
    "suggestedGoals": [{ /* Goal */ }]
  }
}
```

---

### `GET /api/v1/reviews`

List all reviews for the current user (summary view — no `rawText`, no `suggestedGoals` detail).

**Response** `200`
```json
{
  "success": true,
  "data": [
    {
      "id": "string",
      "userId": "string",
      "createdAt": "ISO8601",
      "reviewerContext": "string",
      "extractedFeedback": { /* object */ },
      "suggestedGoalCount": "number"
    }
  ]
}
```

---

### `GET /api/v1/reviews/:id`

Fetch a single review with full detail including `rawText` and expanded `suggestedGoals` (each goal includes its milestones).

**Response** `200`
```json
{
  "success": true,
  "data": {
    "id": "string",
    "userId": "string",
    "createdAt": "ISO8601",
    "reviewerContext": "string",
    "rawText": "string",
    "extractedFeedback": { /* object */ },
    "suggestedGoals": [
      {
        "id": "string",
        "title": "string",
        "description": "string",
        "priority": "string",
        "status": "string",
        "progressPercent": "number",
        "suggestedByAI": "boolean",
        "milestones": [{ /* Milestone row */ }]
      }
    ]
  }
}
```

---

## Goals

Manual and AI-suggested career goals with milestones. Milestones are always fetched inline.

### `GET /api/v1/goals`

List goals filtered by status.

**Query params**
| Param | Type | Default |
|---|---|---|
| `status` | string | `active` |

**Response** `200`
```json
{
  "success": true,
  "data": [
    {
      "id": "string",
      "userId": "string",
      "title": "string",
      "description": "string",
      "sourceReviewId": "string | null",
      "suggestedByAI": "boolean",
      "priority": "string",
      "status": "string",
      "relatedThemes": ["string"],
      "progressPercent": "number",
      "createdAt": "ISO8601",
      "updatedAt": "ISO8601",
      "targetDate": "ISO8601 | null",
      "milestones": [
        {
          "id": "string",
          "goalId": "string",
          "title": "string",
          "status": "string",
          "evidenceEntryIds": ["string"]
        }
      ]
    }
  ]
}
```

---

### `POST /api/v1/goals`

Create a manual goal (`suggestedByAI` set to `false`).

**Request body**
```json
{
  "title": "string (required)",
  "description": "string",
  "priority": "string (default: 'medium')",
  "relatedThemes": ["string"],
  "targetDate": "ISO8601 | null"
}
```

**Response** `201`
```json
{
  "success": true,
  "data": { /* Goal with milestones */ }
}
```

---

### `PATCH /api/v1/goals/:id`

Partial update on a goal. All fields optional.

**Request body**
```json
{
  "status": "string",
  "priority": "string",
  "title": "string",
  "description": "string",
  "targetDate": "ISO8601"
}
```

**Response** `200`
```json
{
  "success": true,
  "data": { /* Goal with milestones */ }
}
```

---

### `GET /api/v1/goals/:id/progress`

Fetch a goal alongside journal-entry evidence. Scans all `entry_analyses.goal_assessments` for mentions of this goal ID.

**Response** `200`
```json
{
  "success": true,
  "data": {
    "goal": { /* Goal with milestones */ },
    "evidence": [
      {
        "date": "ISO8601",
        "evidence": "string",
        "progressDelta": "number"
      }
    ],
    "totalEvidenceCount": "number"
  }
}
```

---

## Action Items

AI-generated tasks extracted from journal entries during analysis. Read-only creation (written by `journalAgent`); only status can be updated.

### `GET /api/v1/action-items`

List action items filtered by status. Also updates `users.open_action_item_count` on status change (see PATCH).

**Query params**
| Param | Type | Default |
|---|---|---|
| `status` | string | `open` |

**Response** `200`
```json
{
  "success": true,
  "data": [
    {
      "id": "string",
      "userId": "string",
      "sourceEntryId": "string",
      "title": "string",
      "dueContext": "string",
      "priority": "string",
      "status": "string",
      "createdAt": "ISO8601"
    }
  ]
}
```

---

### `PATCH /api/v1/action-items/:id`

Update the status of an action item. After updating, recalculates `users.open_action_item_count`.

**Request body**
```json
{
  "status": "string (required — e.g. 'done', 'dismissed')"
}
```

**Response** `200`
```json
{
  "success": true,
  "data": { /* raw action_items row */ }
}
```

---

## Trajectory

Periodic career trajectory analysis. `GET` returns the most recent cached snapshot; `POST /generate` runs a fresh Claude analysis and persists a new snapshot.

### `GET /api/v1/trajectory`

Return the latest trajectory snapshot from DB (no Claude call).

**Query params**
| Param | Type | Default | Notes |
|---|---|---|---|
| `period` | string | `30d` | Accepted: `30d`, `90d`, `all` — currently used only for documentation; snapshot query ignores it |

**Response** `200`
```json
{
  "success": true,
  "data": {
    "id": "string",
    "userId": "string",
    "generatedAt": "ISO8601",
    "periodStart": "ISO8601",
    "periodEnd": "ISO8601",
    "narrativeSummary": "string",
    "keyThemes": ["string"],
    "momentumHistory": [
      {
        "recordedAt": "ISO8601",
        "signal": "string",
        "sentiment": "string",
        "energyLevel": "number"
      }
    ],
    "winCount": "number",
    "challengeCount": "number",
    "resolvedChallengeCount": "number",
    "growthObservations": ["string"],
    "suggestedFocusAreas": ["string"],
    "goalProgressSummaries": [{ /* GoalProgressSummary */ }]
  }
}
```

Returns `{ "success": true, "data": null }` when no snapshot exists yet.

---

### `POST /api/v1/trajectory/generate`

Run a fresh trajectory analysis via Claude (`trajectoryAnalyst` prompts + `callClaudeJson`). Requires at least one analyzed entry in the period; returns `data: null` if there are none. Also updates `goals.progress_percent` for any goals referenced in `goalProgressSummaries`.

**Query params**
| Param | Type | Default | Notes |
|---|---|---|---|
| `period` | string | `30d` | `30d` = last 30 days, `90d` = last 90 days, `all` = all time |

No request body required.

**Response** `200`
```json
{
  "success": true,
  "data": {
    "id": "string",
    "periodStart": "ISO8601",
    "periodEnd": "ISO8601",
    "momentumHistory": [{ /* see GET /trajectory */ }],
    "narrativeSummary": "string",
    "keyThemes": ["string"],
    "winCount": "number",
    "challengeCount": "number",
    "resolvedChallengeCount": "number",
    "growthObservations": ["string"],
    "suggestedFocusAreas": ["string"],
    "goalProgressSummaries": [
      {
        "goalId": "string",
        "progressPercent": "number"
      }
    ]
  }
}
```

---

## Notifications

This is a legacy endpoint. The mobile scheduler no longer calls it; local notifications always use
generic content-free copy (`You have an open Taisa action`) and content-free navigation metadata.

### `POST /api/v1/notifications/checkin-message`

Generate a short, personalized push-notification message using Claude (`buildCheckInSystem` / `buildCheckInUser` from `trajectoryAnalyst` prompts). Max 100 tokens. Falls back to a static string if Claude fails.

No request body required.

**Response** `200`
```json
{
  "success": true,
  "data": {
    "message": "string"
  }
}
```

---

## Error Response Shape

All error responses use a consistent envelope:

```json
{
  "success": false,
  "error": {
    "code": "UPPERCASE_SNAKE_CASE_CODE",
    "message": "Human-readable description"
  }
}
```

Common codes:
| HTTP | Code | Meaning |
|---|---|---|
| 400 | `MISSING_*` / `NO_FILE` | Required field absent |
| 401 | `UNAUTHORIZED` | `x-user-id` header missing |
| 404 | `NOT_FOUND` | Resource not found or not owned by user |
| 500 | `*_FAILED` / `INTERNAL_ERROR` | Server or Claude error |

---

## How to add a new AI endpoint

For new local-first coaching capabilities, extend the shared bounded contract and the stateless
provider-neutral coaching service. Do not load readable user history from backend SQLite and do not
persist provider content. The steps below describe the legacy agent pattern only.

Follow these steps in order. Use `analyze` + `journalAgent` as your reference.

1. **Create the route file**: `backend/src/routes/yourFeature.ts`
   - Mount router handler
   - Validate `x-user-id` header
   - Call your agent function
   - Return result

2. **Mount in `backend/src/index.ts`**:
   ```typescript
   import yourFeatureRouter from './routes/yourFeature';
   app.use('/api/v1/yourFeature', yourFeatureRouter);
   ```

3. **Create the agent**: `backend/src/services/claude/yourFeatureAgent.ts`
   - Load context from DB
   - Call prompt builder
   - Call `callClaudeJson(system, user)`
   - Write result to DB

4. **Create the prompt builder**: `backend/src/prompts/system/yourFeaturePrompt.ts`
   - Export `buildYourFeatureSystem(context): string`
   - Export `buildYourFeatureUser(input): string`
   - Pure functions — no DB or Claude calls

5. **Add the mobile service call** in `mobile/src/services/api.ts` or a new service file.

See `docs/architecture.md` for the full annotated walkthrough of this pattern.

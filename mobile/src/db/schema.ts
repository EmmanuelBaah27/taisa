export const SCHEMA_V1_STATEMENTS: readonly string[] = [
  `CREATE TABLE profile (
    id TEXT PRIMARY KEY NOT NULL,
    current_role TEXT,
    current_company TEXT,
    industry TEXT,
    years_of_experience INTEGER,
    career_stage TEXT,
    current_focus_area TEXT,
    short_term_goal TEXT,
    long_term_goal TEXT,
    coaching_style TEXT,
    accountability_level TEXT,
    reminder_times_json TEXT NOT NULL DEFAULT '[]',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )`,
  `CREATE TABLE conversations (
    id TEXT PRIMARY KEY NOT NULL,
    title TEXT,
    lifecycle TEXT NOT NULL CHECK (lifecycle IN ('active', 'archived')),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    archived_at TEXT,
    idempotency_key TEXT UNIQUE
  )`,
  `CREATE TABLE messages (
    id TEXT PRIMARY KEY NOT NULL,
    conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    parent_message_id TEXT REFERENCES messages(id) ON DELETE SET NULL,
    role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    lifecycle TEXT NOT NULL CHECK (lifecycle IN ('private', 'pending', 'submitted', 'received', 'failed')),
    request_id TEXT UNIQUE,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )`,
  `CREATE TABLE goals (
    id TEXT PRIMARY KEY NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    lifecycle TEXT NOT NULL CHECK (lifecycle IN ('proposed', 'active', 'paused', 'superseded', 'completed', 'rejected', 'archived')),
    priority TEXT CHECK (priority IN ('low', 'medium', 'high')),
    progress_percent INTEGER NOT NULL DEFAULT 0 CHECK (progress_percent BETWEEN 0 AND 100),
    target_date TEXT,
    source_message_id TEXT REFERENCES messages(id) ON DELETE SET NULL,
    supersedes_id TEXT REFERENCES goals(id) ON DELETE SET NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    status_changed_at TEXT NOT NULL,
    idempotency_key TEXT UNIQUE
  )`,
  `CREATE TABLE milestones (
    id TEXT PRIMARY KEY NOT NULL,
    goal_id TEXT NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    lifecycle TEXT NOT NULL CHECK (lifecycle IN ('pending', 'completed', 'archived')),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    completed_at TEXT,
    idempotency_key TEXT UNIQUE
  )`,
  `CREATE TABLE actions (
    id TEXT PRIMARY KEY NOT NULL,
    goal_id TEXT REFERENCES goals(id) ON DELETE SET NULL,
    source_message_id TEXT REFERENCES messages(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    description TEXT,
    lifecycle TEXT NOT NULL CHECK (lifecycle IN ('proposed', 'open', 'completed', 'dropped', 'archived')),
    priority TEXT CHECK (priority IN ('low', 'medium', 'high')),
    due_at TEXT,
    supersedes_id TEXT REFERENCES actions(id) ON DELETE SET NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    status_changed_at TEXT NOT NULL,
    idempotency_key TEXT UNIQUE
  )`,
  `CREATE TABLE action_transitions (
    id TEXT PRIMARY KEY NOT NULL,
    action_id TEXT NOT NULL REFERENCES actions(id) ON DELETE CASCADE,
    from_lifecycle TEXT NOT NULL CHECK (from_lifecycle IN ('proposed', 'open', 'completed', 'dropped', 'archived')),
    to_lifecycle TEXT NOT NULL CHECK (to_lifecycle IN ('proposed', 'open', 'completed', 'dropped', 'archived')),
    source_message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    request_id TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind = 'explicit-user-completion'),
    occurred_at TEXT NOT NULL,
    idempotency_key TEXT NOT NULL UNIQUE
  )`,
  `CREATE TABLE evidence (
    id TEXT PRIMARY KEY NOT NULL,
    statement TEXT NOT NULL,
    occurred_at TEXT NOT NULL,
    source_message_ids_json TEXT NOT NULL DEFAULT '[]',
    goal_ids_json TEXT NOT NULL DEFAULT '[]',
    action_ids_json TEXT NOT NULL DEFAULT '[]',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    idempotency_key TEXT UNIQUE
  )`,
  `CREATE TABLE memory_items (
    id TEXT PRIMARY KEY NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('goal', 'commitment', 'decision', 'preference', 'career_context', 'development_area', 'evidence', 'pattern')),
    statement TEXT NOT NULL,
    provenance TEXT NOT NULL CHECK (provenance IN ('user-stated', 'user-confirmed', 'ai-inferred', 'system-observed')),
    lifecycle TEXT NOT NULL CHECK (lifecycle IN ('proposed', 'active', 'paused', 'superseded', 'completed', 'rejected', 'archived')),
    confidence TEXT NOT NULL CHECK (confidence IN ('tentative', 'supported', 'established')),
    supersedes_id TEXT REFERENCES memory_items(id) ON DELETE SET NULL,
    created_at TEXT NOT NULL,
    confirmed_at TEXT,
    last_supported_at TEXT NOT NULL,
    status_changed_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    idempotency_key TEXT UNIQUE
  )`,
  `CREATE TABLE memory_sources (
    id TEXT PRIMARY KEY NOT NULL,
    memory_item_id TEXT NOT NULL REFERENCES memory_items(id) ON DELETE CASCADE,
    message_id TEXT REFERENCES messages(id) ON DELETE CASCADE,
    evidence_id TEXT REFERENCES evidence(id) ON DELETE CASCADE,
    linked_at TEXT NOT NULL,
    CHECK (
      (message_id IS NOT NULL AND evidence_id IS NULL) OR
      (message_id IS NULL AND evidence_id IS NOT NULL)
    )
  )`,
  `CREATE UNIQUE INDEX memory_sources_message_unique
    ON memory_sources(memory_item_id, message_id)
    WHERE message_id IS NOT NULL`,
  `CREATE UNIQUE INDEX memory_sources_evidence_unique
    ON memory_sources(memory_item_id, evidence_id)
    WHERE evidence_id IS NOT NULL`,
  `CREATE TABLE memory_confirmations (
    id TEXT PRIMARY KEY NOT NULL,
    conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    source_message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    proposal_json TEXT NOT NULL,
    proposal_digest TEXT NOT NULL CHECK (
      length(proposal_digest) = 64 AND proposal_digest NOT GLOB '*[^0-9a-f]*'
    ),
    presentation_kind TEXT NOT NULL DEFAULT 'proposal'
      CHECK (presentation_kind IN ('proposal', 'clarification')),
    clarification_question TEXT,
    resolution_json TEXT,
    resolution_digest TEXT CHECK (
      resolution_digest IS NULL OR (
        length(resolution_digest) = 64 AND resolution_digest NOT GLOB '*[^0-9a-f]*'
      )
    ),
    status TEXT NOT NULL CHECK (status IN ('pending', 'confirmed', 'consumed')),
    staged_at TEXT NOT NULL,
    confirmed_at TEXT,
    consumed_at TEXT,
    local_user_action_id TEXT UNIQUE,
    local_user_action_kind TEXT CHECK (
      local_user_action_kind IS NULL OR local_user_action_kind = 'explicit-confirm'
    ),
    local_user_action_at TEXT,
    consumed_by_idempotency_id TEXT UNIQUE,
    CHECK (
      (presentation_kind = 'proposal' AND clarification_question IS NULL)
      OR
      (presentation_kind = 'clarification' AND length(trim(clarification_question)) > 0)
    ),
    CHECK (
      (status = 'pending' AND resolution_json IS NULL AND resolution_digest IS NULL
        AND confirmed_at IS NULL AND local_user_action_id IS NULL
        AND local_user_action_kind IS NULL AND local_user_action_at IS NULL
        AND consumed_at IS NULL AND consumed_by_idempotency_id IS NULL)
      OR
      (status = 'confirmed' AND resolution_json IS NOT NULL AND resolution_digest IS NOT NULL
        AND confirmed_at IS NOT NULL AND local_user_action_id IS NOT NULL
        AND local_user_action_kind = 'explicit-confirm' AND local_user_action_at IS NOT NULL
        AND consumed_at IS NULL AND consumed_by_idempotency_id IS NULL)
      OR
      (status = 'consumed' AND resolution_json IS NOT NULL AND resolution_digest IS NOT NULL
        AND confirmed_at IS NOT NULL AND local_user_action_id IS NOT NULL
        AND local_user_action_kind = 'explicit-confirm' AND local_user_action_at IS NOT NULL
        AND consumed_at IS NOT NULL AND consumed_by_idempotency_id IS NOT NULL)
    )
  )`,
  `CREATE TABLE coaching_requests (
    id TEXT PRIMARY KEY NOT NULL,
    intent_id TEXT NOT NULL UNIQUE,
    conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_message_id TEXT NOT NULL UNIQUE REFERENCES messages(id) ON DELETE CASCADE,
    transcription_request_id TEXT UNIQUE,
    kind TEXT NOT NULL CHECK (kind IN ('text', 'voice')),
    status TEXT NOT NULL CHECK (status IN (
      'transcription-pending', 'transcription-failed',
      'transcript-confirmation-required', 'coaching-pending',
      'coaching-failed', 'completed', 'abandoned'
    )),
    audio_uri TEXT,
    audio_duration_seconds REAL CHECK (
      audio_duration_seconds IS NULL OR audio_duration_seconds >= 0
    ),
    transcript_confirmed_at TEXT,
    assistant_message_id TEXT UNIQUE REFERENCES messages(id) ON DELETE SET NULL,
    stance TEXT CHECK (stance IS NULL OR stance IN ('mirror', 'nudge', 'challenge', 'direct')),
    context_manifest_json TEXT,
    error_code TEXT,
    attempt_count INTEGER NOT NULL CHECK (attempt_count >= 1),
    submitted_at TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    CHECK (
      (kind = 'text' AND transcription_request_id IS NULL AND audio_uri IS NULL
        AND audio_duration_seconds IS NULL)
      OR
      (kind = 'voice' AND transcription_request_id IS NOT NULL
        AND audio_duration_seconds IS NOT NULL
        AND (
          audio_uri IS NOT NULL
          OR status NOT IN ('transcription-pending', 'transcription-failed')
        ))
    )
  )`,
  `CREATE TABLE audio_cleanup_queue (
    audio_uri TEXT PRIMARY KEY NOT NULL CHECK (length(trim(audio_uri)) > 0),
    enqueued_at TEXT NOT NULL,
    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    last_attempt_at TEXT,
    last_error_code TEXT CHECK (
      last_error_code IS NULL OR (
        length(last_error_code) BETWEEN 1 AND 64
        AND substr(last_error_code, 1, 1) GLOB '[A-Z]'
        AND last_error_code NOT GLOB '*[^A-Z0-9_]*'
      )
    ),
    CHECK (
      (attempt_count = 0 AND last_attempt_at IS NULL AND last_error_code IS NULL)
      OR
      (attempt_count > 0 AND last_attempt_at IS NOT NULL AND last_error_code IS NOT NULL)
    )
  )`,
  `CREATE TABLE usage_receipts (
    id TEXT PRIMARY KEY NOT NULL,
    request_id TEXT NOT NULL UNIQUE,
    provider TEXT NOT NULL CHECK (provider IN ('anthropic', 'openai')),
    model TEXT NOT NULL,
    input_tokens INTEGER CHECK (input_tokens IS NULL OR input_tokens >= 0),
    output_tokens INTEGER CHECK (output_tokens IS NULL OR output_tokens >= 0),
    audio_seconds REAL CHECK (audio_seconds IS NULL OR audio_seconds >= 0),
    estimated_cost_usd REAL NOT NULL CHECK (estimated_cost_usd >= 0),
    recorded_at TEXT NOT NULL
  )`,
  `CREATE TABLE migration_state (
    id TEXT PRIMARY KEY NOT NULL,
    schema_version INTEGER NOT NULL,
    authority TEXT NOT NULL CHECK (authority IN ('backend', 'device')),
    imported_at TEXT,
    source_digest TEXT,
    updated_at TEXT NOT NULL
  )`,
  `CREATE TABLE mutation_receipts (
    idempotency_id TEXT PRIMARY KEY NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    operation TEXT NOT NULL,
    fingerprint_version INTEGER NOT NULL CHECK (fingerprint_version = 1),
    payload_digest TEXT NOT NULL CHECK (
      length(payload_digest) = 64 AND payload_digest NOT GLOB '*[^0-9a-f]*'
    ),
    recorded_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
  )`,
  `CREATE INDEX messages_conversation_created_idx ON messages(conversation_id, created_at)`,
  `CREATE INDEX coaching_requests_conversation_status_updated_idx
    ON coaching_requests(conversation_id, status, updated_at DESC)`,
  `CREATE INDEX coaching_requests_active_audio_uri_idx
    ON coaching_requests(audio_uri)
    WHERE audio_uri IS NOT NULL AND status NOT IN ('completed', 'abandoned')`,
  `CREATE INDEX audio_cleanup_queue_enqueued_idx
    ON audio_cleanup_queue(enqueued_at, audio_uri)`,
  `CREATE INDEX memory_confirmations_conversation_status_staged_idx
    ON memory_confirmations(conversation_id, status, staged_at DESC)`,
  `CREATE INDEX goals_lifecycle_updated_idx ON goals(lifecycle, updated_at)`,
  `CREATE INDEX actions_lifecycle_updated_idx ON actions(lifecycle, updated_at)`,
  `CREATE INDEX memory_items_lifecycle_type_idx ON memory_items(lifecycle, type)`,
  `CREATE VIRTUAL TABLE message_search USING fts5(
    content,
    content='messages',
    content_rowid='rowid'
  )`,
  `CREATE TRIGGER messages_search_insert AFTER INSERT ON messages BEGIN
    INSERT INTO message_search(rowid, content) VALUES (new.rowid, new.content);
  END`,
  `CREATE TRIGGER messages_search_delete AFTER DELETE ON messages BEGIN
    INSERT INTO message_search(message_search, rowid, content) VALUES ('delete', old.rowid, old.content);
  END`,
  `CREATE TRIGGER messages_search_update AFTER UPDATE OF content ON messages BEGIN
    INSERT INTO message_search(message_search, rowid, content) VALUES ('delete', old.rowid, old.content);
    INSERT INTO message_search(rowid, content) VALUES (new.rowid, new.content);
  END`,
  `CREATE VIRTUAL TABLE evidence_search USING fts5(
    statement,
    content='evidence',
    content_rowid='rowid'
  )`,
  `CREATE TRIGGER evidence_search_insert AFTER INSERT ON evidence BEGIN
    INSERT INTO evidence_search(rowid, statement) VALUES (new.rowid, new.statement);
  END`,
  `CREATE TRIGGER evidence_search_delete AFTER DELETE ON evidence BEGIN
    INSERT INTO evidence_search(evidence_search, rowid, statement) VALUES ('delete', old.rowid, old.statement);
  END`,
  `CREATE TRIGGER evidence_search_update AFTER UPDATE OF statement ON evidence BEGIN
    INSERT INTO evidence_search(evidence_search, rowid, statement) VALUES ('delete', old.rowid, old.statement);
    INSERT INTO evidence_search(rowid, statement) VALUES (new.rowid, new.statement);
  END`,
];

export const SCHEMA_V2_STATEMENTS: readonly string[] = [
  "ALTER TABLE conversations ADD COLUMN preferred_input_mode TEXT NOT NULL DEFAULT 'text' CHECK (preferred_input_mode IN ('voice', 'text'))",
];

export const SCHEMA_V3_STATEMENTS: readonly string[] = [
  `CREATE TABLE response_feedback (
    response_message_id TEXT PRIMARY KEY NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    reaction TEXT NOT NULL CHECK (reaction IN ('helpful', 'unhelpful')),
    note TEXT CHECK (note IS NULL OR length(note) <= 1000),
    share_status TEXT NOT NULL DEFAULT 'local-only'
      CHECK (share_status IN ('local-only', 'previewed', 'shared')),
    share_consent_at TEXT,
    share_receipt_id TEXT UNIQUE,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    CHECK (
      (share_status IN ('local-only', 'previewed')
        AND share_consent_at IS NULL AND share_receipt_id IS NULL)
      OR
      (share_status = 'shared' AND share_consent_at IS NOT NULL AND share_receipt_id IS NOT NULL)
    )
  )`,
];

export const SCHEMA_V4_STATEMENTS: readonly string[] = [
  'DROP INDEX coaching_requests_conversation_status_updated_idx',
  'DROP INDEX coaching_requests_active_audio_uri_idx',
  'ALTER TABLE coaching_requests RENAME TO coaching_requests_v3',
  `CREATE TABLE coaching_requests (
    id TEXT PRIMARY KEY NOT NULL,
    intent_id TEXT NOT NULL UNIQUE,
    conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_message_id TEXT UNIQUE REFERENCES messages(id) ON DELETE CASCADE,
    transcription_request_id TEXT UNIQUE,
    kind TEXT NOT NULL CHECK (kind IN ('text', 'voice')),
    status TEXT NOT NULL CHECK (status IN (
      'transcription-pending', 'transcription-failed',
      'transcription-uncertain', 'no-speech',
      'transcript-confirmation-required', 'coaching-pending',
      'coaching-failed', 'completed', 'abandoned'
    )),
    audio_uri TEXT,
    audio_duration_seconds REAL CHECK (
      audio_duration_seconds IS NULL OR audio_duration_seconds >= 0
    ),
    transcript_draft TEXT,
    transcript_confirmed_at TEXT,
    assistant_message_id TEXT UNIQUE REFERENCES messages(id) ON DELETE SET NULL,
    stance TEXT CHECK (stance IS NULL OR stance IN ('mirror', 'nudge', 'challenge', 'direct')),
    context_manifest_json TEXT,
    error_code TEXT,
    attempt_count INTEGER NOT NULL CHECK (attempt_count >= 1),
    submitted_at TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    CHECK (
      (kind = 'text' AND transcription_request_id IS NULL AND audio_uri IS NULL
        AND audio_duration_seconds IS NULL AND transcript_draft IS NULL
        AND user_message_id IS NOT NULL)
      OR
      (kind = 'voice' AND transcription_request_id IS NOT NULL
        AND audio_duration_seconds IS NOT NULL
        AND (
          audio_uri IS NOT NULL
          OR status NOT IN ('transcription-pending', 'transcription-failed', 'transcription-uncertain')
        ))
    ),
    CHECK (
      status != 'transcription-uncertain'
      OR (user_message_id IS NULL AND transcript_draft IS NOT NULL
        AND length(trim(transcript_draft)) > 0)
    ),
    CHECK (status != 'no-speech' OR user_message_id IS NULL)
  )`,
  `INSERT INTO coaching_requests (
    id, intent_id, conversation_id, user_message_id, transcription_request_id, kind, status,
    audio_uri, audio_duration_seconds, transcript_draft, transcript_confirmed_at,
    assistant_message_id, stance, context_manifest_json, error_code, attempt_count,
    submitted_at, created_at, updated_at
  ) SELECT
    id, intent_id, conversation_id, user_message_id, transcription_request_id, kind, status,
    audio_uri, audio_duration_seconds, NULL, transcript_confirmed_at,
    assistant_message_id, stance, context_manifest_json, error_code, attempt_count,
    submitted_at, created_at, updated_at
  FROM coaching_requests_v3`,
  'DROP TABLE coaching_requests_v3',
  `CREATE INDEX coaching_requests_conversation_status_updated_idx
    ON coaching_requests(conversation_id, status, updated_at DESC)`,
  `CREATE INDEX coaching_requests_active_audio_uri_idx
    ON coaching_requests(audio_uri)
    WHERE audio_uri IS NOT NULL AND status NOT IN ('completed', 'abandoned')`,
];

export const SCHEMA_V5_STATEMENTS: readonly string[] = [
  `CREATE TABLE projects (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('active', 'archived')),
    source_id TEXT NOT NULL,
    revision INTEGER NOT NULL CHECK (revision > 0),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    idempotency_key TEXT UNIQUE
  )`,
  `CREATE TABLE work_records (
    id TEXT PRIMARY KEY NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('task', 'followup', 'blocker', 'decision')),
    title TEXT NOT NULL,
    project_id TEXT REFERENCES projects(id) ON DELETE SET NULL,
    status TEXT NOT NULL,
    freshness TEXT NOT NULL CHECK (freshness IN ('current', 'needs_confirmation', 'stale')),
    planned_week TEXT,
    planned_day TEXT,
    source_id TEXT NOT NULL,
    revision INTEGER NOT NULL CHECK (revision > 0),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    last_confirmed_at TEXT,
    idempotency_key TEXT UNIQUE,
    CHECK (
      (kind = 'task' AND status IN ('open', 'completed', 'removed')) OR
      (kind = 'followup' AND status IN ('waiting', 'completed', 'rescheduled', 'cancelled')) OR
      (kind = 'blocker' AND status IN ('active', 'being_resolved', 'resolved', 'no_longer_relevant')) OR
      (kind = 'decision' AND status IN ('current', 'reopened', 'superseded', 'reversed'))
    )
  )`,
  `CREATE TABLE work_relationships (
    id TEXT PRIMARY KEY NOT NULL,
    record_id TEXT NOT NULL REFERENCES work_records(id) ON DELETE CASCADE,
    conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('primary', 'supporting')),
    contribution TEXT NOT NULL CHECK (contribution IN ('planning', 'status', 'blocker', 'decision', 'outcome', 'evidence')),
    source_revision INTEGER NOT NULL CHECK (source_revision > 0),
    created_at TEXT NOT NULL,
    idempotency_key TEXT UNIQUE
  )`,
  `CREATE UNIQUE INDEX work_relationships_primary_unique
    ON work_relationships(record_id) WHERE role = 'primary'`,
  `CREATE UNIQUE INDEX work_relationships_pair_unique
    ON work_relationships(record_id, conversation_id)`,
  `CREATE TABLE record_events (
    id TEXT PRIMARY KEY NOT NULL,
    record_id TEXT NOT NULL REFERENCES work_records(id) ON DELETE CASCADE,
    operation TEXT NOT NULL,
    prior_value_json TEXT,
    resulting_value_json TEXT NOT NULL,
    source_id TEXT NOT NULL,
    occurred_at TEXT NOT NULL,
    idempotency_key TEXT NOT NULL UNIQUE
  )`,
  `CREATE TABLE proposals (
    id TEXT PRIMARY KEY NOT NULL,
    type TEXT NOT NULL,
    source_id TEXT NOT NULL,
    source_revision INTEGER NOT NULL CHECK (source_revision > 0),
    evidence_ids_json TEXT NOT NULL,
    evidence_fingerprint TEXT NOT NULL,
    reasoning TEXT NOT NULL,
    effect_json TEXT NOT NULL,
    ambiguity TEXT NOT NULL CHECK (ambiguity IN ('strong', 'ambiguous')),
    admission TEXT NOT NULL CHECK (admission IN ('pending', 'admitted', 'suppressed')),
    resolution TEXT NOT NULL CHECK (resolution IN ('unapplied', 'accepted', 'rejected', 'expired')),
    revalidation TEXT NOT NULL CHECK (revalidation IN ('valid', 'stale', 'conflicted')),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    idempotency_key TEXT UNIQUE
  )`,
  `CREATE INDEX proposals_review_idx
    ON proposals(admission, resolution, revalidation, updated_at DESC)`,
  `CREATE INDEX proposals_fingerprint_idx ON proposals(evidence_fingerprint, type)`,
  `CREATE TABLE insights (
    id TEXT PRIMARY KEY NOT NULL,
    kind TEXT NOT NULL CHECK (kind = 'operational'),
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    freshness TEXT NOT NULL CHECK (freshness IN ('current', 'stale', 'contradictory')),
    evidence_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )`,
  `CREATE TABLE growth_reflections (
    id TEXT PRIMARY KEY NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    state TEXT NOT NULL CHECK (state IN ('proposed', 'confirmed', 'rejected')),
    evidence_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )`,
  `CREATE TABLE experiments (
    id TEXT PRIMARY KEY NOT NULL,
    title TEXT NOT NULL,
    hypothesis TEXT NOT NULL,
    state TEXT NOT NULL CHECK (state IN ('proposed', 'active', 'completed', 'abandoned')),
    source_reflection_id TEXT REFERENCES growth_reflections(id) ON DELETE SET NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )`,
  `CREATE TABLE weekly_periods (
    id TEXT PRIMARY KEY NOT NULL,
    starts_on TEXT NOT NULL UNIQUE,
    ends_on TEXT NOT NULL UNIQUE,
    state TEXT NOT NULL CHECK (state IN ('open', 'auto_closed_unreviewed', 'reviewed')),
    reviewed_at TEXT,
    closed_at TEXT
  )`,
  `CREATE TABLE weekly_period_snapshots (
    id TEXT PRIMARY KEY NOT NULL,
    period_id TEXT NOT NULL REFERENCES weekly_periods(id) ON DELETE CASCADE,
    record_ids_json TEXT NOT NULL,
    created_at TEXT NOT NULL
  )`,
  `CREATE TABLE capability_states (
    operation TEXT PRIMARY KEY NOT NULL CHECK (operation IN (
      'complete_explicit_task', 'associate_existing_project',
      'apply_strong_task_conversation_link', 'update_explicit_followup_status',
      'update_explicit_blocker_status', 'update_explicit_project_status'
    )),
    policy_version INTEGER NOT NULL CHECK (policy_version > 0),
    state TEXT NOT NULL CHECK (state IN ('learning', 'ready', 'permission_granted', 'trial', 'trusted', 'ask_me')),
    permission_granted_at TEXT,
    relevant_examples INTEGER NOT NULL DEFAULT 0 CHECK (relevant_examples >= 0),
    corrections INTEGER NOT NULL DEFAULT 0 CHECK (corrections >= 0),
    contradictions INTEGER NOT NULL DEFAULT 0 CHECK (contradictions >= 0),
    latest_evidence_at TEXT,
    clean_trial_outcomes INTEGER NOT NULL DEFAULT 0 CHECK (clean_trial_outcomes >= 0),
    updated_at TEXT NOT NULL
  )`,
  `CREATE TABLE operation_events (
    id TEXT PRIMARY KEY NOT NULL,
    operation TEXT NOT NULL,
    target_id TEXT NOT NULL,
    source_id TEXT NOT NULL,
    prior_revision INTEGER NOT NULL,
    resulting_revision INTEGER NOT NULL,
    visibility TEXT NOT NULL CHECK (visibility IN ('trial', 'history')),
    undoable INTEGER NOT NULL CHECK (undoable IN (0, 1)),
    undone_at TEXT,
    created_at TEXT NOT NULL,
    idempotency_key TEXT NOT NULL UNIQUE
  )`,
  `CREATE TABLE behavior_events (
    id TEXT PRIMARY KEY NOT NULL,
    category TEXT NOT NULL,
    event_type TEXT NOT NULL,
    source_id TEXT,
    occurred_at TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    idempotency_key TEXT NOT NULL UNIQUE
  )`,
  `CREATE TABLE behavior_aggregates (
    id TEXT PRIMARY KEY NOT NULL,
    category TEXT NOT NULL,
    period_start TEXT NOT NULL,
    period_end TEXT NOT NULL,
    event_count INTEGER NOT NULL CHECK (event_count >= 0),
    confirmed_history_id TEXT,
    UNIQUE(category, period_start, period_end)
  )`,
  `CREATE TABLE local_notifications (
    id TEXT PRIMARY KEY NOT NULL,
    source_type TEXT NOT NULL CHECK (source_type IN ('work_record', 'proposal', 'insight', 'weekly_review', 'operation')),
    source_id TEXT NOT NULL,
    grouping_key TEXT NOT NULL,
    read_state TEXT NOT NULL CHECK (read_state IN ('unread', 'read')),
    disposition TEXT NOT NULL CHECK (disposition IN ('active', 'snoozed', 'dismissed')),
    snoozed_until TEXT,
    created_at TEXT NOT NULL,
    idempotency_key TEXT UNIQUE
  )`,
  `CREATE INDEX work_records_home_idx
    ON work_records(planned_week, status, freshness, updated_at DESC)`,
  `CREATE INDEX record_events_record_idx ON record_events(record_id, occurred_at DESC)`,
  `CREATE INDEX behavior_events_expiry_idx ON behavior_events(expires_at)`,
  `CREATE INDEX local_notifications_group_idx
    ON local_notifications(grouping_key, disposition, read_state, created_at DESC)`,
  `INSERT OR IGNORE INTO work_records
    (id, kind, title, project_id, status, freshness, planned_week, planned_day,
     source_id, revision, created_at, updated_at, last_confirmed_at, idempotency_key)
   SELECT id, 'task', title, NULL,
     CASE lifecycle
       WHEN 'completed' THEN 'completed'
       WHEN 'dropped' THEN 'removed'
       WHEN 'archived' THEN 'removed'
       ELSE 'open'
     END,
     'current', NULL, CASE WHEN due_at IS NULL THEN NULL ELSE substr(due_at, 1, 10) END,
     COALESCE(source_message_id, id), 1, created_at, updated_at, status_changed_at,
     'migrate-action:' || id
   FROM actions
   WHERE lifecycle IN ('open', 'completed', 'dropped', 'archived')`,
];

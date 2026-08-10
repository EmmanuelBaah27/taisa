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
    memory_item_id TEXT NOT NULL REFERENCES memory_items(id) ON DELETE CASCADE,
    message_id TEXT REFERENCES messages(id) ON DELETE CASCADE,
    evidence_id TEXT REFERENCES evidence(id) ON DELETE CASCADE,
    linked_at TEXT NOT NULL,
    PRIMARY KEY (memory_item_id, message_id, evidence_id),
    CHECK (message_id IS NOT NULL OR evidence_id IS NOT NULL)
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
  `CREATE INDEX messages_conversation_created_idx ON messages(conversation_id, created_at)`,
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

import GRDB

enum TaisaSchema {
    static let currentVersion = 1

    static func createVersion1(in db: Database) throws {
        // IDs are opaque UUID strings; every persisted time is UTC milliseconds.
        // This database-only schema deliberately has no audio path or URI column.
        let statements = [
            """
            CREATE TABLE profile (
                id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
                display_name TEXT NOT NULL DEFAULT '',
                headline TEXT NOT NULL DEFAULT '',
                biography TEXT NOT NULL DEFAULT '',
                updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= 0)
            )
            """,
            """
            CREATE TABLE conversations (
                id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
                title TEXT NOT NULL DEFAULT '',
                created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
                updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms)
            )
            """,
            """
            CREATE TABLE messages (
                id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
                conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
                body TEXT NOT NULL,
                created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0)
            )
            """,
            """
            CREATE TABLE goals (
                id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
                title TEXT NOT NULL,
                detail TEXT NOT NULL DEFAULT '',
                status TEXT NOT NULL CHECK (status IN ('active', 'completed', 'archived')),
                created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
                updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms)
            )
            """,
            """
            CREATE TABLE milestones (
                id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
                goal_id TEXT NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                status TEXT NOT NULL CHECK (status IN ('open', 'completed')),
                target_at_ms INTEGER CHECK (target_at_ms >= 0),
                updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= 0)
            )
            """,
            """
            CREATE TABLE actions (
                id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
                goal_id TEXT REFERENCES goals(id) ON DELETE SET NULL,
                title TEXT NOT NULL,
                detail TEXT NOT NULL DEFAULT '',
                status TEXT NOT NULL CHECK (status IN ('open', 'completed', 'archived')),
                due_at_ms INTEGER CHECK (due_at_ms >= 0),
                created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
                updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms)
            )
            """,
            """
            CREATE TABLE evidence (
                id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
                goal_id TEXT REFERENCES goals(id) ON DELETE SET NULL,
                action_id TEXT REFERENCES actions(id) ON DELETE SET NULL,
                title TEXT NOT NULL,
                detail TEXT NOT NULL DEFAULT '',
                occurred_at_ms INTEGER NOT NULL CHECK (occurred_at_ms >= 0),
                created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0)
            )
            """,
            """
            CREATE TABLE memory_items (
                id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
                kind TEXT NOT NULL,
                content TEXT NOT NULL,
                status TEXT NOT NULL CHECK (status IN ('active', 'suppressed')),
                created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
                updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms)
            )
            """,
            """
            CREATE TABLE memory_sources (
                id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
                memory_item_id TEXT NOT NULL REFERENCES memory_items(id) ON DELETE CASCADE,
                source_type TEXT NOT NULL,
                source_id TEXT NOT NULL CHECK (length(source_id) = 36),
                created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
                UNIQUE (memory_item_id, source_type, source_id)
            )
            """,
            """
            CREATE TABLE sync_devices (
                id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
                vault_id TEXT NOT NULL CHECK (length(vault_id) = 36),
                registration_envelope BLOB NOT NULL,
                acknowledged_counter INTEGER NOT NULL DEFAULT 0 CHECK (acknowledged_counter >= 0),
                registered_at_ms INTEGER NOT NULL CHECK (registered_at_ms >= 0),
                removed_at_ms INTEGER CHECK (removed_at_ms >= registered_at_ms)
            )
            """,
            """
            CREATE TABLE field_versions (
                id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
                entity_type TEXT NOT NULL,
                entity_id TEXT NOT NULL CHECK (length(entity_id) = 36),
                field_name TEXT NOT NULL,
                version_id TEXT NOT NULL CHECK (length(version_id) = 36),
                parent_version_id TEXT CHECK (parent_version_id IS NULL OR length(parent_version_id) = 36),
                device_id TEXT NOT NULL CHECK (length(device_id) = 36),
                device_counter INTEGER NOT NULL CHECK (device_counter >= 0),
                updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= 0),
                UNIQUE (entity_type, entity_id, field_name, version_id),
                UNIQUE (entity_type, entity_id, field_name, device_id, device_counter)
            )
            """,
            """
            CREATE TABLE conflicts (
                id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
                entity_type TEXT NOT NULL,
                entity_id TEXT NOT NULL CHECK (length(entity_id) = 36),
                field_name TEXT NOT NULL,
                local_version_id TEXT NOT NULL CHECK (length(local_version_id) = 36),
                remote_version_id TEXT NOT NULL CHECK (length(remote_version_id) = 36),
                local_value BLOB NOT NULL,
                remote_value BLOB NOT NULL,
                created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
                resolved_at_ms INTEGER CHECK (resolved_at_ms >= created_at_ms),
                UNIQUE (entity_type, entity_id, field_name, local_version_id, remote_version_id)
            )
            """,
            """
            CREATE TABLE outbox (
                id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
                mutation_id TEXT NOT NULL UNIQUE CHECK (length(mutation_id) = 36),
                entity_type TEXT NOT NULL,
                entity_id TEXT NOT NULL CHECK (length(entity_id) = 36),
                payload BLOB NOT NULL,
                status TEXT NOT NULL CHECK (status IN ('pending', 'retrying', 'acknowledged')),
                retry_category TEXT,
                attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
                created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
                acknowledged_at_ms INTEGER CHECK (acknowledged_at_ms >= created_at_ms)
            )
            """,
            """
            CREATE TABLE inbox_quarantine (
                id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
                envelope_id TEXT NOT NULL UNIQUE CHECK (length(envelope_id) = 36),
                ciphertext BLOB NOT NULL,
                reason_code TEXT NOT NULL,
                received_at_ms INTEGER NOT NULL CHECK (received_at_ms >= 0)
            )
            """,
            """
            CREATE TABLE tombstones (
                id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
                entity_type TEXT NOT NULL,
                entity_id TEXT NOT NULL CHECK (length(entity_id) = 36),
                deletion_version_id TEXT NOT NULL UNIQUE CHECK (length(deletion_version_id) = 36),
                deleted_at_ms INTEGER NOT NULL CHECK (deleted_at_ms >= 0),
                UNIQUE (entity_type, entity_id)
            )
            """,
            """
            CREATE TABLE sync_state (
                id INTEGER PRIMARY KEY NOT NULL CHECK (id = 1),
                vault_id TEXT CHECK (vault_id IS NULL OR length(vault_id) = 36),
                account_fingerprint BLOB,
                change_token BLOB,
                engine_state BLOB,
                updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= 0)
            )
            """,
            """
            CREATE TABLE vault_metadata (
                id INTEGER PRIMARY KEY NOT NULL CHECK (id = 1),
                vault_id TEXT NOT NULL UNIQUE CHECK (length(vault_id) = 36),
                key_version INTEGER NOT NULL CHECK (key_version > 0),
                wrapped_key BLOB NOT NULL,
                algorithm TEXT NOT NULL,
                updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= 0)
            )
            """,
            """
            CREATE TABLE snapshot_manifests (
                id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
                vault_id TEXT NOT NULL CHECK (length(vault_id) = 36),
                source_device_id TEXT NOT NULL CHECK (length(source_device_id) = 36),
                schema_version INTEGER NOT NULL CHECK (schema_version > 0),
                envelope_version INTEGER NOT NULL CHECK (envelope_version > 0),
                manifest BLOB NOT NULL,
                archive_digest BLOB NOT NULL,
                archive_size_bytes INTEGER NOT NULL CHECK (archive_size_bytes >= 0),
                created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0)
            )
            """,
            """
            CREATE TABLE migration_state (
                version INTEGER PRIMARY KEY NOT NULL CHECK (version > 0),
                applied_at_ms INTEGER NOT NULL CHECK (applied_at_ms >= 0)
            )
            """,
            "CREATE INDEX messages_by_conversation ON messages(conversation_id, created_at_ms)",
            "CREATE INDEX milestones_by_goal ON milestones(goal_id)",
            "CREATE INDEX actions_by_goal_status ON actions(goal_id, status)",
            "CREATE INDEX evidence_by_date ON evidence(occurred_at_ms)",
            "CREATE INDEX memory_sources_by_source ON memory_sources(source_type, source_id)",
            "CREATE INDEX field_versions_by_field ON field_versions(entity_type, entity_id, field_name)",
            "CREATE INDEX conflicts_unresolved ON conflicts(resolved_at_ms)",
            "CREATE INDEX outbox_pending ON outbox(status, created_at_ms)",
            "CREATE INDEX tombstones_by_date ON tombstones(deleted_at_ms)",
            "CREATE INDEX snapshots_by_date ON snapshot_manifests(created_at_ms)",
        ]
        for statement in statements { try db.execute(sql: statement) }
    }
}

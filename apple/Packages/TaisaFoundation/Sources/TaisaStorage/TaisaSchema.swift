import GRDB

enum TaisaSchema {
    struct MigrationLedgerEntry: Equatable, Sendable {
        let version: Int
        let identifier: String
        let predecessor: String?
        let body: [String]
    }

    static let currentVersion = 5

    static func createVersion1(in db: Database) throws {
        for statement in version1Statements { try db.execute(sql: statement) }
    }

    static func createVersion2(in db: Database) throws {
        for statement in version2Statements { try db.execute(sql: statement) }
    }

    static func createVersion3(in db: Database) throws {
        for statement in version3Statements { try db.execute(sql: statement) }
    }

    static func createVersion4(in db: Database) throws {
        for statement in version4Statements { try db.execute(sql: statement) }
    }

    static func createVersion5(in db: Database) throws {
        for statement in version5Statements { try db.execute(sql: statement) }
    }

    static var migrationLedger: [MigrationLedgerEntry] {
        [
            .init(version: 1, identifier: "v1", predecessor: nil, body: version1Statements),
            .init(version: 2, identifier: "v2", predecessor: "v1", body: version2Statements),
            .init(version: 3, identifier: "v3", predecessor: "v2", body: version3Statements),
            .init(version: 4, identifier: "v4", predecessor: "v3", body: version4Statements),
            .init(version: 5, identifier: "v5", predecessor: "v4", body: version5Statements),
        ]
    }

    static func validateMigrationLedger(_ entries: [MigrationLedgerEntry]) throws {
        guard !entries.isEmpty else { throw StorageError.unsupportedMigration }
        var versions = Set<Int>()
        var identifiers = Set<String>()
        for (index, entry) in entries.enumerated() {
            let expectedVersion = index + 1
            let expectedIdentifier = "v\(expectedVersion)"
            let expectedPredecessor = index == 0 ? nil : "v\(index)"
            guard entry.version == expectedVersion,
                  entry.identifier == expectedIdentifier,
                  entry.predecessor == expectedPredecessor,
                  !entry.body.isEmpty,
                  versions.insert(entry.version).inserted,
                  identifiers.insert(entry.identifier).inserted else {
                throw StorageError.unsupportedMigration
            }
        }
    }

    // The stored DDL is also the canonical v1 integrity contract. Comparing it
    // on reopen catches removed FKs, checks, PKs, types, and unique constraints
    // even when the table still has every expected column name.
    private static let version1Statements: [String] = [
        // IDs are opaque UUID strings; every persisted time is UTC milliseconds.
        // This database-only schema deliberately has no audio path or URI column.
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
            "CREATE INDEX evidence_by_goal ON evidence(goal_id)",
            "CREATE INDEX evidence_by_action ON evidence(action_id)",
            "CREATE INDEX memory_sources_by_source ON memory_sources(source_type, source_id)",
            "CREATE INDEX field_versions_by_field ON field_versions(entity_type, entity_id, field_name)",
            "CREATE INDEX conflicts_unresolved ON conflicts(resolved_at_ms)",
            "CREATE INDEX outbox_pending ON outbox(status, created_at_ms)",
            "CREATE INDEX tombstones_by_date ON tombstones(deleted_at_ms)",
            "CREATE INDEX snapshots_by_date ON snapshot_manifests(created_at_ms)",
    ]

    private static let version2Statements: [String] = [
        """
        CREATE TABLE voice_turns (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
            transcription_request_id TEXT NOT NULL UNIQUE CHECK (length(transcription_request_id) = 36),
            transcription_idempotency_key TEXT NOT NULL UNIQUE,
            coaching_request_id TEXT NOT NULL UNIQUE CHECK (length(coaching_request_id) = 36),
            coaching_idempotency_key TEXT NOT NULL UNIQUE,
            state TEXT NOT NULL CHECK (state IN ('draft', 'recording', 'paused', 'queued', 'transcribing', 'transcriptClear', 'transcriptUncertain', 'awaitingTranscriptConfirmation', 'coaching', 'completed', 'noSpeech', 'recoverableFailure', 'terminalFailure', 'cancelled', 'discarded', 'resumeRequiresConfirmation')),
            stage TEXT NOT NULL CHECK (stage IN ('capture', 'transcription', 'coaching', 'cleanup', 'finished')),
            audio_file_id TEXT,
            audio_sha256 TEXT,
            audio_duration_ms INTEGER CHECK (audio_duration_ms IS NULL OR audio_duration_ms >= 0),
            accepted_transcript TEXT,
            uncertain_transcript TEXT,
            retry_count INTEGER NOT NULL DEFAULT 0 CHECK (retry_count >= 0),
            next_retry_at_ms INTEGER CHECK (next_retry_at_ms IS NULL OR next_retry_at_ms >= 0),
            failure_code TEXT,
            transcription_receipt TEXT,
            coaching_receipt TEXT,
            user_message_id TEXT UNIQUE REFERENCES messages(id) ON DELETE SET NULL,
            assistant_message_id TEXT UNIQUE REFERENCES messages(id) ON DELETE SET NULL,
            cleanup_state TEXT NOT NULL CHECK (cleanup_state IN ('notRequired', 'pending', 'completed')),
            created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
            updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
            CHECK (audio_file_id IS NULL OR length(audio_file_id) > 0),
            CHECK (accepted_transcript IS NULL OR uncertain_transcript IS NULL)
        )
        """,
        """
        CREATE TABLE audio_cleanup_queue (
            turn_id TEXT PRIMARY KEY NOT NULL REFERENCES voice_turns(id) ON DELETE CASCADE,
            audio_file_id TEXT NOT NULL,
            completed_at_ms INTEGER CHECK (completed_at_ms IS NULL OR completed_at_ms >= 0)
        )
        """,
        "CREATE INDEX voice_turns_by_conversation ON voice_turns(conversation_id, updated_at_ms)",
        "CREATE INDEX voice_turns_by_state ON voice_turns(state, next_retry_at_ms)",
    ]

    private static let version3Statements: [String] = [
        """
        CREATE TABLE weekly_placements (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            action_id TEXT NOT NULL REFERENCES actions(id) ON DELETE CASCADE,
            week_start_ms INTEGER NOT NULL CHECK (week_start_ms >= 0),
            planned_day_ms INTEGER CHECK (planned_day_ms >= week_start_ms),
            created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
            updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
            UNIQUE (action_id, week_start_ms)
        )
        """,
        """
        CREATE TABLE work_events (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            action_id TEXT NOT NULL REFERENCES actions(id) ON DELETE CASCADE,
            kind TEXT NOT NULL CHECK (kind IN ('created', 'placed', 'moved', 'completed', 'restored', 'removed')),
            from_week_start_ms INTEGER CHECK (from_week_start_ms >= 0),
            to_week_start_ms INTEGER CHECK (to_week_start_ms >= 0),
            source_type TEXT NOT NULL,
            source_id TEXT CHECK (source_id IS NULL OR length(source_id) = 36),
            occurred_at_ms INTEGER NOT NULL CHECK (occurred_at_ms >= 0)
        )
        """,
        """
        CREATE TABLE insights (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            body TEXT NOT NULL,
            status TEXT NOT NULL CHECK (status IN ('confirmed', 'review_needed', 'superseded', 'retired')),
            is_time_sensitive INTEGER NOT NULL DEFAULT 0 CHECK (is_time_sensitive IN (0, 1)),
            home_eligible_until_ms INTEGER CHECK (home_eligible_until_ms >= 0),
            created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
            updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms)
        )
        """,
        """
        CREATE TABLE insight_sources (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            insight_id TEXT NOT NULL REFERENCES insights(id) ON DELETE CASCADE,
            source_type TEXT NOT NULL,
            source_id TEXT NOT NULL CHECK (length(source_id) = 36),
            excerpt TEXT NOT NULL DEFAULT '',
            created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
            UNIQUE (insight_id, source_type, source_id)
        )
        """,
        """
        CREATE TABLE insight_revisions (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            insight_id TEXT REFERENCES insights(id) ON DELETE CASCADE,
            proposed_body TEXT NOT NULL,
            status TEXT NOT NULL CHECK (status IN ('proposed', 'accepted', 'rejected')),
            source_type TEXT NOT NULL,
            source_id TEXT CHECK (source_id IS NULL OR length(source_id) = 36),
            created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
            resolved_at_ms INTEGER CHECK (resolved_at_ms >= created_at_ms)
        )
        """,
        "CREATE INDEX weekly_placements_by_week ON weekly_placements(week_start_ms, planned_day_ms)",
        "CREATE INDEX work_events_by_action ON work_events(action_id, occurred_at_ms)",
        "CREATE INDEX insights_by_status ON insights(status, updated_at_ms)",
        "CREATE INDEX insight_sources_by_insight ON insight_sources(insight_id)",
        "CREATE INDEX insight_revisions_by_insight ON insight_revisions(insight_id, created_at_ms)",
    ]

    private static let version4Statements: [String] = [
        "ALTER TABLE conversations ADD COLUMN lifecycle TEXT NOT NULL DEFAULT 'completed' CHECK (lifecycle IN ('draft', 'active', 'completed'))",
        "ALTER TABLE conversations ADD COLUMN title_authority TEXT NOT NULL DEFAULT 'user' CHECK (title_authority IN ('localFallback', 'assistantSuggested', 'user'))",
        """
        CREATE TABLE conversation_drafts (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            conversation_id TEXT NOT NULL UNIQUE REFERENCES conversations(id) ON DELETE CASCADE,
            input_mode TEXT NOT NULL CHECK (input_mode IN ('voice', 'text')),
            text TEXT,
            voice_turn_id TEXT UNIQUE REFERENCES voice_turns(id) ON DELETE CASCADE,
            recovery_kind TEXT NOT NULL CHECK (recovery_kind IN ('saved', 'recovered', 'retryableTranscription', 'retryableCoaching')),
            created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
            updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= created_at_ms),
            CHECK ((input_mode = 'text' AND text IS NOT NULL AND voice_turn_id IS NULL)
                OR (input_mode = 'voice' AND text IS NULL AND voice_turn_id IS NOT NULL))
        )
        """,
        """
        CREATE TABLE message_revisions (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
            original_body TEXT NOT NULL,
            replacement_message_id TEXT REFERENCES messages(id) ON DELETE SET NULL,
            created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0)
        )
        """,
        "CREATE INDEX conversation_drafts_by_updated ON conversation_drafts(updated_at_ms DESC, created_at_ms DESC)",
        "CREATE INDEX message_revisions_by_message ON message_revisions(message_id, created_at_ms)",
    ]

    private static let version5Statements: [String] = [
        """
        CREATE TABLE career_work_events (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            entity_type TEXT NOT NULL CHECK (entity_type IN ('goal', 'milestone', 'action')),
            entity_id TEXT NOT NULL CHECK (length(entity_id) = 36),
            transition TEXT NOT NULL CHECK (transition IN ('created', 'paused', 'resumed', 'completed', 'reopened', 'archived', 'restored')),
            from_status TEXT,
            to_status TEXT NOT NULL,
            source_type TEXT NOT NULL CHECK (source_type IN ('user', 'proposal', 'undo', 'migration')),
            source_id TEXT CHECK (source_id IS NULL OR length(source_id) = 36),
            occurred_at_ms INTEGER NOT NULL CHECK (occurred_at_ms >= 0),
            UNIQUE (entity_type, entity_id, occurred_at_ms, transition)
        )
        """,
        """
        CREATE TABLE career_work_archives (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            entity_type TEXT NOT NULL CHECK (entity_type IN ('goal', 'milestone', 'action')),
            entity_id TEXT NOT NULL CHECK (length(entity_id) = 36),
            archived_at_ms INTEGER NOT NULL CHECK (archived_at_ms >= 0),
            restored_at_ms INTEGER CHECK (restored_at_ms IS NULL OR restored_at_ms >= archived_at_ms),
            UNIQUE (entity_type, entity_id, archived_at_ms)
        )
        """,
        """
        CREATE TABLE evidence_provenance (
            evidence_id TEXT PRIMARY KEY NOT NULL REFERENCES evidence(id) ON DELETE CASCADE,
            origin_type TEXT NOT NULL CHECK (origin_type IN ('user', 'action', 'conversation', 'import')),
            origin_id TEXT CHECK (origin_id IS NULL OR length(origin_id) = 36),
            supersedes_evidence_id TEXT REFERENCES evidence(id) ON DELETE SET NULL,
            created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
            CHECK (supersedes_evidence_id IS NULL OR supersedes_evidence_id != evidence_id)
        )
        """,
        """
        CREATE TABLE career_work_proposal_receipts (
            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
            proposal_id TEXT NOT NULL UNIQUE CHECK (length(proposal_id) = 36),
            target_type TEXT NOT NULL CHECK (target_type IN ('goal', 'milestone', 'action', 'evidence')),
            target_id TEXT NOT NULL CHECK (length(target_id) = 36),
            target_version_id TEXT NOT NULL CHECK (length(target_version_id) = 36),
            payload_digest TEXT NOT NULL CHECK (length(payload_digest) > 0),
            decision TEXT NOT NULL CHECK (decision IN ('accepted', 'corrected', 'rejected', 'undone')),
            resolved_at_ms INTEGER NOT NULL CHECK (resolved_at_ms >= 0)
        )
        """,
        """
        CREATE TABLE capability_states (
            capability_id TEXT PRIMARY KEY NOT NULL CHECK (length(capability_id) > 0),
            state TEXT NOT NULL CHECK (state IN ('learning', 'ready', 'trial', 'trusted')),
            decision_source TEXT NOT NULL CHECK (decision_source = 'user'),
            transport_source TEXT NOT NULL CHECK (transport_source IN ('direct', 'import', 'restore')),
            decided_at_ms INTEGER NOT NULL CHECK (decided_at_ms >= 0),
            updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= decided_at_ms)
        )
        """,
        "CREATE INDEX career_work_events_by_entity ON career_work_events(entity_type, entity_id, occurred_at_ms)",
        "CREATE INDEX career_work_archives_by_entity ON career_work_archives(entity_type, entity_id, archived_at_ms)",
        "CREATE UNIQUE INDEX career_work_one_active_archive ON career_work_archives(entity_type, entity_id) WHERE restored_at_ms IS NULL",
        "CREATE INDEX evidence_provenance_by_origin ON evidence_provenance(origin_type, origin_id)",
        "CREATE INDEX career_work_receipts_by_target ON career_work_proposal_receipts(target_type, target_id, resolved_at_ms)",
        "CREATE INDEX capability_states_by_state ON capability_states(state, updated_at_ms)",
    ]

    static func validateVersion1(in db: Database, allowingConversationExtensions: Bool = false) throws {
        let requiredColumns: [String: Set<String>] = [
            "profile": ["id", "display_name", "headline", "biography", "updated_at_ms"],
            "conversations": ["id", "title", "created_at_ms", "updated_at_ms"],
            "messages": ["id", "conversation_id", "role", "body", "created_at_ms"],
            "goals": ["id", "title", "detail", "status", "created_at_ms", "updated_at_ms"],
            "milestones": ["id", "goal_id", "title", "status", "target_at_ms", "updated_at_ms"],
            "actions": ["id", "goal_id", "title", "detail", "status", "due_at_ms", "created_at_ms", "updated_at_ms"],
            "evidence": ["id", "goal_id", "action_id", "title", "detail", "occurred_at_ms", "created_at_ms"],
            "memory_items": ["id", "kind", "content", "status", "created_at_ms", "updated_at_ms"],
            "memory_sources": ["id", "memory_item_id", "source_type", "source_id", "created_at_ms"],
            "sync_devices": ["id", "vault_id", "registration_envelope", "acknowledged_counter", "registered_at_ms", "removed_at_ms"],
            "field_versions": ["id", "entity_type", "entity_id", "field_name", "version_id", "parent_version_id", "device_id", "device_counter", "updated_at_ms"],
            "conflicts": ["id", "entity_type", "entity_id", "field_name", "local_version_id", "remote_version_id", "local_value", "remote_value", "created_at_ms", "resolved_at_ms"],
            "outbox": ["id", "mutation_id", "entity_type", "entity_id", "payload", "status", "retry_category", "attempts", "created_at_ms", "acknowledged_at_ms"],
            "inbox_quarantine": ["id", "envelope_id", "ciphertext", "reason_code", "received_at_ms"],
            "tombstones": ["id", "entity_type", "entity_id", "deletion_version_id", "deleted_at_ms"],
            "sync_state": ["id", "vault_id", "account_fingerprint", "change_token", "engine_state", "updated_at_ms"],
            "vault_metadata": ["id", "vault_id", "key_version", "wrapped_key", "algorithm", "updated_at_ms"],
            "snapshot_manifests": ["id", "vault_id", "source_device_id", "schema_version", "envelope_version", "manifest", "archive_digest", "archive_size_bytes", "created_at_ms"],
            "migration_state": ["version", "applied_at_ms"],
        ]
        do {
            for (table, expected) in requiredColumns {
                guard try db.tableExists(table) else { throw StorageError.schemaMismatch }
                let actual = Set(try db.columns(in: table).map(\.name))
                guard actual == expected || (allowingConversationExtensions && table == "conversations" && actual.isSuperset(of: expected)) else { throw StorageError.schemaMismatch }
            }
            // V1's supported producer is this canonical migration. SQLite can
            // rewrite equivalent CREATE text during manual ALTER/restore; such
            // rewritten schemas require an explicit migration, not guessed
            // normalization that could erase constraint differences.
            for statement in version1Statements where statement.hasPrefix("CREATE TABLE ") {
                let name = String(statement.split(separator: " ", maxSplits: 3)[2])
                if allowingConversationExtensions && name == "conversations" { continue }
                let stored = try String.fetchOne(
                    db,
                    sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
                    arguments: [name]
                )
                guard stored == statement else { throw StorageError.schemaMismatch }
            }
        } catch {
            throw StorageError.schemaMismatch
        }
    }

    static func validateVersion2(in db: Database, allowingConversationExtensions: Bool = false) throws {
        try validateVersion1(in: db, allowingConversationExtensions: allowingConversationExtensions)
        let requiredColumns: [String: Set<String>] = [
            "voice_turns": ["id", "conversation_id", "transcription_request_id", "transcription_idempotency_key", "coaching_request_id", "coaching_idempotency_key", "state", "stage", "audio_file_id", "audio_sha256", "audio_duration_ms", "accepted_transcript", "uncertain_transcript", "retry_count", "next_retry_at_ms", "failure_code", "transcription_receipt", "coaching_receipt", "user_message_id", "assistant_message_id", "cleanup_state", "created_at_ms", "updated_at_ms"],
            "audio_cleanup_queue": ["turn_id", "audio_file_id", "completed_at_ms"],
        ]
        do {
            for (table, expected) in requiredColumns {
                guard try db.tableExists(table), Set(try db.columns(in: table).map(\.name)) == expected else {
                    throw StorageError.schemaMismatch
                }
            }
            for statement in version2Statements where statement.hasPrefix("CREATE TABLE ") {
                let name = String(statement.split(separator: " ", maxSplits: 3)[2])
                let stored = try String.fetchOne(
                    db,
                    sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
                    arguments: [name]
                )
                guard stored == statement else { throw StorageError.schemaMismatch }
            }
        } catch {
            throw StorageError.schemaMismatch
        }
    }

    static func validateVersion3(in db: Database, allowingConversationExtensions: Bool = false) throws {
        try validateVersion2(in: db, allowingConversationExtensions: allowingConversationExtensions)
        let requiredColumns: [String: Set<String>] = [
            "weekly_placements": ["id", "action_id", "week_start_ms", "planned_day_ms", "created_at_ms", "updated_at_ms"],
            "work_events": ["id", "action_id", "kind", "from_week_start_ms", "to_week_start_ms", "source_type", "source_id", "occurred_at_ms"],
            "insights": ["id", "body", "status", "is_time_sensitive", "home_eligible_until_ms", "created_at_ms", "updated_at_ms"],
            "insight_sources": ["id", "insight_id", "source_type", "source_id", "excerpt", "created_at_ms"],
            "insight_revisions": ["id", "insight_id", "proposed_body", "status", "source_type", "source_id", "created_at_ms", "resolved_at_ms"],
        ]
        do {
            for (table, expected) in requiredColumns {
                guard try db.tableExists(table), Set(try db.columns(in: table).map(\.name)) == expected else {
                    throw StorageError.schemaMismatch
                }
            }
            for statement in version3Statements where statement.hasPrefix("CREATE TABLE ") {
                let name = String(statement.split(separator: " ", maxSplits: 3)[2])
                let stored = try String.fetchOne(
                    db,
                    sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
                    arguments: [name]
                )
                guard stored == statement else { throw StorageError.schemaMismatch }
            }
        } catch {
            throw StorageError.schemaMismatch
        }
    }

    static func validateVersion4(in db: Database) throws {
        try validateVersion3(in: db, allowingConversationExtensions: true)
        do {
            guard Set(try db.columns(in: "conversations").map(\.name)) == [
                "id", "title", "lifecycle", "title_authority", "created_at_ms", "updated_at_ms",
            ] else { throw StorageError.schemaMismatch }
            let requiredColumns: [String: Set<String>] = [
                "conversation_drafts": ["id", "conversation_id", "input_mode", "text", "voice_turn_id", "recovery_kind", "created_at_ms", "updated_at_ms"],
                "message_revisions": ["id", "message_id", "original_body", "replacement_message_id", "created_at_ms"],
            ]
            for (table, expected) in requiredColumns {
                guard try db.tableExists(table), Set(try db.columns(in: table).map(\.name)) == expected else {
                    throw StorageError.schemaMismatch
                }
            }
            for statement in version4Statements where statement.hasPrefix("CREATE TABLE ") {
                let name = String(statement.split(separator: " ", maxSplits: 3)[2])
                let stored = try String.fetchOne(
                    db,
                    sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
                    arguments: [name]
                )
                guard stored == statement else { throw StorageError.schemaMismatch }
            }
        } catch {
            throw StorageError.schemaMismatch
        }
    }

    static func validateVersion5(in db: Database) throws {
        try validateVersion4(in: db)
        let requiredColumns: [String: Set<String>] = [
            "career_work_events": ["id", "entity_type", "entity_id", "transition", "from_status", "to_status", "source_type", "source_id", "occurred_at_ms"],
            "career_work_archives": ["id", "entity_type", "entity_id", "archived_at_ms", "restored_at_ms"],
            "evidence_provenance": ["evidence_id", "origin_type", "origin_id", "supersedes_evidence_id", "created_at_ms"],
            "career_work_proposal_receipts": ["id", "proposal_id", "target_type", "target_id", "target_version_id", "payload_digest", "decision", "resolved_at_ms"],
            "capability_states": ["capability_id", "state", "decision_source", "transport_source", "decided_at_ms", "updated_at_ms"],
        ]
        do {
            for (table, expected) in requiredColumns {
                guard try db.tableExists(table), Set(try db.columns(in: table).map(\.name)) == expected else {
                    throw StorageError.schemaMismatch
                }
            }
            for statement in version5Statements where statement.hasPrefix("CREATE TABLE ") {
                let name = String(statement.split(separator: " ", maxSplits: 3)[2])
                let stored = try String.fetchOne(
                    db,
                    sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
                    arguments: [name]
                )
                guard stored == statement else { throw StorageError.schemaMismatch }
            }
            for statement in version5Statements where statement.hasPrefix("CREATE INDEX ") || statement.hasPrefix("CREATE UNIQUE INDEX ") {
                let parts = statement.split(separator: " ", maxSplits: 4)
                let name = String(statement.hasPrefix("CREATE UNIQUE INDEX ") ? parts[3] : parts[2])
                let stored = try String.fetchOne(
                    db,
                    sql: "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = ?",
                    arguments: [name]
                )
                guard stored == statement else { throw StorageError.schemaMismatch }
            }
        } catch {
            throw StorageError.schemaMismatch
        }
    }
}

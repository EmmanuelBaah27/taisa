import Foundation
import GRDB
import Testing
@testable import TaisaStorage

@Suite(.serialized) struct TaisaMigratorTests {
    @Test func compactVersionThreeCheckSyntaxUpgradesWithoutRecoveryDetour() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let queue = try fixture.makeKeyedQueue()
        var legacy = DatabaseMigrator()
        for version in 1...5 {
            legacy.registerMigration("v\(version)", foreignKeyChecks: .immediate) { db in
                switch version {
                case 1: try TaisaSchema.createVersion1(in: db)
                case 2: try TaisaSchema.createVersion2(in: db)
                case 3:
                    try db.execute(sql: "ALTER TABLE conversations ADD COLUMN lifecycle TEXT NOT NULL DEFAULT 'completed' CHECK (lifecycle IN ('draft', 'active', 'completed'))")
                    try db.execute(sql: "ALTER TABLE conversations ADD COLUMN title_authority TEXT NOT NULL DEFAULT 'user' CHECK (title_authority IN ('localFallback', 'assistantSuggested', 'user'))")
                    try db.execute(sql: Self.compactConversationDraftsDDL)
                    try db.execute(sql: """
                        CREATE TABLE message_revisions (
                            id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
                            message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
                            original_body TEXT NOT NULL,
                            replacement_message_id TEXT REFERENCES messages(id) ON DELETE SET NULL,
                            created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0)
                        )
                        """)
                    try db.execute(sql: "CREATE INDEX conversation_drafts_by_updated ON conversation_drafts(updated_at_ms DESC, created_at_ms DESC)")
                    try db.execute(sql: "CREATE INDEX message_revisions_by_message ON message_revisions(message_id, created_at_ms)")
                case 4: try TaisaSchema.createVersion4(in: db)
                case 5: try TaisaSchema.createVersion5(in: db)
                default: break
                }
                try db.execute(sql: "INSERT INTO migration_state (version, applied_at_ms) VALUES (?, ?)", arguments: [version, version])
                try db.execute(sql: "PRAGMA user_version = \(version)")
            }
        }
        try legacy.migrate(queue)
        let profileID = UUID().uuidString
        try await queue.write { db in
            try db.execute(sql: "INSERT INTO profile (id, display_name, updated_at_ms) VALUES (?, 'Preserved', 1)", arguments: [profileID])
        }
        try queue.close()

        let store = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let state = try await store.read { db in
            return (
                try Int.fetchOne(db, sql: "PRAGMA user_version"),
                try String.fetchOne(db, sql: "SELECT display_name FROM profile WHERE id = ?", arguments: [profileID])
            )
        }
#expect(state.0 == 8)
        #expect(state.1 == "Preserved")
    }

    private static let compactConversationDraftsDDL = """
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
    """

    @Test func versionEightMigratesLegacyActionsWithoutChangingIdentityOrRelationships() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let queue = try fixture.makeKeyedQueue()
        var legacy = DatabaseMigrator()
        for entry in TaisaSchema.migrationLedger.prefix(7) {
            legacy.registerMigration(entry.identifier, foreignKeyChecks: entry.version == 6 ? .deferred : .immediate) { db in
                switch entry.version {
                case 1: try TaisaSchema.createVersion1(in: db)
                case 2: try TaisaSchema.createVersion2(in: db)
                case 3: try TaisaSchema.createVersion3(in: db)
                case 4: try TaisaSchema.createVersion4(in: db)
                case 5: try TaisaSchema.createVersion5(in: db)
                case 6: try TaisaSchema.createVersion6(in: db)
                case 7: try TaisaSchema.createVersion7(in: db)
                default: throw MigrationInterruption.injected
                }
                try db.execute(sql: "INSERT INTO migration_state (version, applied_at_ms) VALUES (?, ?)", arguments: [entry.version, entry.version])
                try db.execute(sql: "PRAGMA user_version = \(entry.version)")
            }
        }
        try legacy.migrate(queue)

        let goalID = UUID().uuidString
        let actionID = UUID().uuidString
        let evidenceID = UUID().uuidString
        let placementID = UUID().uuidString
        try await queue.write { db in
            try db.execute(sql: "INSERT INTO goals (id, title, status, created_at_ms, updated_at_ms) VALUES (?, 'Goal', 'active', 1, 1)", arguments: [goalID])
            try db.execute(sql: "INSERT INTO actions (id, goal_id, title, status, due_at_ms, created_at_ms, updated_at_ms) VALUES (?, ?, 'Preserved action', 'open', 86_400_000, 1, 2)", arguments: [actionID, goalID])
            try db.execute(sql: "INSERT INTO evidence (id, goal_id, action_id, title, occurred_at_ms, created_at_ms) VALUES (?, ?, ?, 'Existing evidence', 2, 2)", arguments: [evidenceID, goalID, actionID])
            try db.execute(sql: "INSERT INTO weekly_placements (id, action_id, week_start_ms, created_at_ms, updated_at_ms) VALUES (?, ?, 0, 2, 2)", arguments: [placementID, actionID])
        }
        try queue.close()

        let store = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let state = try await store.read { db in
            let action = try Row.fetchOne(db, sql: "SELECT id, goal_id, milestone_id, status, due_day, origin, created_at_ms, updated_at_ms FROM actions WHERE id = ?", arguments: [actionID])
            return (
                try Int.fetchOne(db, sql: "PRAGMA user_version"),
                action?["id"] as String?,
                action?["goal_id"] as String?,
                action?["milestone_id"] as String?,
                action?["status"] as String?,
                action?["due_day"] as String?,
                action?["origin"] as String?,
                action?["created_at_ms"] as Int64?,
                action?["updated_at_ms"] as Int64?,
                try Int.fetchOne(db, sql: "SELECT count(*) FROM evidence WHERE id = ? AND action_id = ?", arguments: [evidenceID, actionID]),
                try Int.fetchOne(db, sql: "SELECT count(*) FROM weekly_placements WHERE id = ? AND action_id = ?", arguments: [placementID, actionID]),
                try db.tableExists("action_checklist_items"),
                try db.tableExists("action_events"),
                try Int.fetchOne(db, sql: "SELECT count(*) FROM action_events WHERE action_id = ?", arguments: [actionID]),
                try Int.fetchOne(db, sql: "SELECT count(*) FROM pragma_foreign_key_check")
            )
        }
        #expect(state.0 == 8)
        #expect(state.1 == actionID)
        #expect(state.2 == goalID)
        #expect(state.3 == nil)
        #expect(state.4 == "active")
        #expect(state.5 == nil)
        #expect(state.6 == "manual")
        #expect(state.7 == 1)
        #expect(state.8 == 2)
        #expect(state.9 == 1)
        #expect(state.10 == 1)
        #expect(state.11)
        #expect(state.12)
        #expect(state.13 == 0)
        #expect(state.14 == 0)
    }

    @Test func interruptedVersionEightMigrationLeavesVersionSevenAndActionUnchanged() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let queue = try fixture.makeKeyedQueue()
        var legacy = DatabaseMigrator()
        for entry in TaisaSchema.migrationLedger.prefix(7) {
            legacy.registerMigration(entry.identifier, foreignKeyChecks: entry.version == 6 ? .deferred : .immediate) { db in
                switch entry.version {
                case 1: try TaisaSchema.createVersion1(in: db)
                case 2: try TaisaSchema.createVersion2(in: db)
                case 3: try TaisaSchema.createVersion3(in: db)
                case 4: try TaisaSchema.createVersion4(in: db)
                case 5: try TaisaSchema.createVersion5(in: db)
                case 6: try TaisaSchema.createVersion6(in: db)
                case 7: try TaisaSchema.createVersion7(in: db)
                default: throw MigrationInterruption.injected
                }
                try db.execute(sql: "INSERT INTO migration_state (version, applied_at_ms) VALUES (?, ?)", arguments: [entry.version, entry.version])
                try db.execute(sql: "PRAGMA user_version = \(entry.version)")
            }
        }
        try legacy.migrate(queue)
        let actionID = UUID().uuidString
        try await queue.write { db in
            try db.execute(sql: "INSERT INTO actions (id, title, status, created_at_ms, updated_at_ms) VALUES (?, 'Unchanged', 'open', 1, 1)", arguments: [actionID])
        }

        #expect(throws: StorageError.migrationFailed) {
            try TaisaMigrator.migrate(queue, from: 7, createVersion8: { db in
                try TaisaSchema.createVersion8(in: db)
                throw MigrationInterruption.injected
            })
        }
        let state = try await queue.read { db in
            (
                try Int.fetchOne(db, sql: "PRAGMA user_version"),
                try String.fetchOne(db, sql: "SELECT status FROM actions WHERE id = ?", arguments: [actionID]),
                try db.tableExists("action_events"),
                try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
            )
        }
        #expect(state.0 == 7)
        #expect(state.1 == "open")
        #expect(!state.2)
        #expect(state.3 == ["v1", "v2", "v3", "v4", "v5", "v6", "v7"])
    }

    @Test func versionEightRejectsInvalidCanonicalActionValues() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let store = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        for values in [
            ("open", "2026-10-23", "manual"),
            ("active", "2026-02-30", "manual"),
            ("active", "2026-10-23", "conversation"),
        ] {
            await #expect(throws: DatabaseError.self) {
                try await store.write { db in
                    try db.execute(
                        sql: "INSERT INTO actions (id, title, status, due_day, origin, created_at_ms, updated_at_ms) VALUES (?, 'Invalid', ?, ?, ?, 1, 1)",
                        arguments: [UUID().uuidString, values.0, values.1, values.2]
                    )
                }
            }
        }
    }

    @Test func versionSixPreservesGoalsAndPermitsPausedLifecycle() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let queue = try fixture.makeKeyedQueue()
        var legacy = DatabaseMigrator()
        for entry in TaisaSchema.migrationLedger.prefix(5) {
            legacy.registerMigration(entry.identifier, foreignKeyChecks: .immediate) { db in
                switch entry.version {
                case 1: try TaisaSchema.createVersion1(in: db)
                case 2: try TaisaSchema.createVersion2(in: db)
                case 3: try TaisaSchema.createVersion3(in: db)
                case 4: try TaisaSchema.createVersion4(in: db)
                case 5: try TaisaSchema.createVersion5(in: db)
                default: throw MigrationInterruption.injected
                }
                try db.execute(
                    sql: "INSERT INTO migration_state (version, applied_at_ms) VALUES (?, ?)",
                    arguments: [entry.version, entry.version]
                )
                try db.execute(sql: "PRAGMA user_version = \(entry.version)")
            }
        }
        try legacy.migrate(queue)
        let goalID = UUID().uuidString
        let milestoneID = UUID().uuidString
        let actionID = UUID().uuidString
        let evidenceID = UUID().uuidString
        try await queue.write { db in
            try db.execute(
                sql: "INSERT INTO goals (id, title, detail, status, created_at_ms, updated_at_ms) VALUES (?, 'Preserved', '', 'active', 1, 1)",
                arguments: [goalID]
            )
            try db.execute(
                sql: "INSERT INTO milestones (id, goal_id, title, status, updated_at_ms) VALUES (?, ?, 'Milestone', 'open', 1)",
                arguments: [milestoneID, goalID]
            )
            try db.execute(
                sql: "INSERT INTO actions (id, goal_id, title, status, created_at_ms, updated_at_ms) VALUES (?, ?, 'Action', 'open', 1, 1)",
                arguments: [actionID, goalID]
            )
            try db.execute(
                sql: "INSERT INTO evidence (id, goal_id, action_id, title, occurred_at_ms, created_at_ms) VALUES (?, ?, ?, 'Evidence', 1, 1)",
                arguments: [evidenceID, goalID, actionID]
            )
        }
        try queue.close()

        let store = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        try await store.write { db in
            try db.execute(sql: "UPDATE goals SET status = 'paused', updated_at_ms = 2 WHERE id = ?", arguments: [goalID])
        }
        let state = try await store.read { db in
            (
                try Int.fetchOne(db, sql: "PRAGMA user_version"),
                try String.fetchOne(db, sql: "SELECT title FROM goals WHERE id = ?", arguments: [goalID]),
                try String.fetchOne(db, sql: "SELECT status FROM goals WHERE id = ?", arguments: [goalID]),
                try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier"),
                try Int.fetchOne(db, sql: "SELECT count(*) FROM milestones WHERE id = ? AND goal_id = ?", arguments: [milestoneID, goalID]),
                try Int.fetchOne(db, sql: "SELECT count(*) FROM actions WHERE id = ? AND goal_id = ?", arguments: [actionID, goalID]),
                try Int.fetchOne(db, sql: "SELECT count(*) FROM evidence WHERE id = ? AND goal_id = ? AND action_id = ?", arguments: [evidenceID, goalID, actionID]),
                try Int.fetchOne(db, sql: "SELECT count(*) FROM pragma_foreign_key_check")
            )
        }
        #expect(state.0 == 8)
        #expect(state.1 == "Preserved")
        #expect(state.2 == "paused")
#expect(state.3 == ["v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8"])
        #expect(state.4 == 1)
        #expect(state.5 == 1)
        #expect(state.6 == 1)
        #expect(state.7 == 0)
    }

    @Test func currentSchemaContainsCoordinatedCareerWorkCapabilityAndCombinedContracts() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let store = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let state = try await store.read { db in
            (
                try Int.fetchOne(db, sql: "PRAGMA user_version"),
                try db.tableExists("career_work_events"),
                try db.tableExists("career_work_archives"),
                try db.tableExists("evidence_provenance"),
                try db.tableExists("career_work_proposal_receipts"),
                try db.tableExists("capability_states"),
                try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier"),
                try Int.fetchAll(db, sql: "SELECT version FROM migration_state ORDER BY version")
            )
        }
        #expect(state.0 == 8)
        #expect(state.1)
        #expect(state.2)
        #expect(state.3)
        #expect(state.4)
        #expect(state.5)
#expect(state.6 == ["v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8"])
#expect(state.7 == [1, 2, 3, 4, 5, 6, 7, 8])
    }

    @Test func populatedMainVersionThreeStoreUpgradesLosslesslyToCurrent() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let queue = try fixture.makeKeyedQueue()
        var legacy = DatabaseMigrator()
        legacy.registerMigration("v1", foreignKeyChecks: .immediate) { db in
            try TaisaSchema.createVersion1(in: db)
            try db.execute(sql: "INSERT INTO migration_state (version, applied_at_ms) VALUES (1, 1)")
            try db.execute(sql: "PRAGMA user_version = 1")
        }
        legacy.registerMigration("v2", foreignKeyChecks: .immediate) { db in
            try TaisaSchema.createVersion2(in: db)
            try db.execute(sql: "INSERT INTO migration_state (version, applied_at_ms) VALUES (2, 2)")
            try db.execute(sql: "PRAGMA user_version = 2")
        }
        legacy.registerMigration("v3", foreignKeyChecks: .immediate) { db in
            try TaisaSchema.createVersion3(in: db)
            try db.execute(sql: "INSERT INTO migration_state (version, applied_at_ms) VALUES (3, 3)")
            try db.execute(sql: "PRAGMA user_version = 3")
        }
        try legacy.migrate(queue)
        let profileID = UUID().uuidString
        try await queue.write { db in
            try db.execute(sql: "INSERT INTO profile (id, display_name, updated_at_ms) VALUES (?, 'Preserve', 1)", arguments: [profileID])
        }
        try queue.close()

        let store = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let state = try await store.read { db in
            (
                try Int.fetchOne(db, sql: "PRAGMA user_version"),
                try String.fetchOne(db, sql: "SELECT display_name FROM profile WHERE id = ?", arguments: [profileID]),
                try db.tableExists("capability_states")
            )
        }
        #expect(state.0 == 8)
        #expect(state.1 == "Preserve")
        #expect(state.2)
    }

    @Test func interruptedVersionFourMigrationLeavesVersionThreeAndUserDataUnchanged() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let queue = try fixture.makeKeyedQueue()
        #expect(throws: StorageError.migrationFailed) {
            try TaisaMigrator.migrate(queue, from: 0, createVersion4: { db in
                try TaisaSchema.createVersion4(in: db)
                throw MigrationInterruption.injected
            })
        }
        let state = try await queue.read { db in
            (
                try Int.fetchOne(db, sql: "PRAGMA user_version"),
                try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier"),
                try Int.fetchAll(db, sql: "SELECT version FROM migration_state ORDER BY version"),
                try db.tableExists("capability_states")
            )
        }
        #expect(state.0 == 3)
        #expect(state.1 == ["v1", "v2", "v3"])
        #expect(state.2 == [1, 2, 3])
        #expect(!state.3)
    }

    @Test func missingVersionFourIndexIsRejected() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue()
        try await raw.write { db in try db.execute(sql: "DROP INDEX capability_states_by_state") }
        await #expect(throws: StorageError.schemaMismatch) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
    }

    @Test func missingVersionFiveIndexIsRejected() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue()
        try await raw.write { db in try db.execute(sql: "DROP INDEX weekly_placements_by_week") }
        await #expect(throws: StorageError.schemaMismatch) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
    }

    @Test func migrationLedgerRejectsDivergentDuplicateAndSkippedVersion() throws {
        let divergent = [
            TaisaSchema.MigrationLedgerEntry(version: 1, identifier: "v1", predecessor: nil, body: ["SELECT 1"]),
            TaisaSchema.MigrationLedgerEntry(version: 1, identifier: "v1", predecessor: "v1", body: ["SELECT 2"]),
        ]
        #expect(throws: StorageError.unsupportedMigration) {
            try TaisaSchema.validateMigrationLedger(divergent)
        }

        let skipped = [
            TaisaSchema.MigrationLedgerEntry(version: 1, identifier: "v1", predecessor: nil, body: ["SELECT 1"]),
            TaisaSchema.MigrationLedgerEntry(version: 3, identifier: "v3", predecessor: "v1", body: ["SELECT 3"]),
        ]
        #expect(throws: StorageError.unsupportedMigration) {
            try TaisaSchema.validateMigrationLedger(skipped)
        }
    }

    @Test func capabilityProvenanceKeepsUserAuthoritySeparateFromTransport() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let store = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        await #expect(throws: DatabaseError.self) {
            try await store.write { db in
                try db.execute(sql: "INSERT INTO capability_states (capability_id, state, decision_source, transport_source, decided_at_ms, updated_at_ms) VALUES ('voice', 'ready', 'restore', 'restore', 1, 1)")
            }
        }
        try await store.write { db in
            try db.execute(sql: "INSERT INTO capability_states (capability_id, state, decision_source, transport_source, decided_at_ms, updated_at_ms) VALUES ('voice', 'ready', 'user', 'restore', 1, 1)")
        }
    }

    @Test func onlyOneActiveArchiveExistsPerCareerWorkEntity() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let store = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let entityID = UUID().uuidString
        try await store.write { db in
            try db.execute(sql: "INSERT INTO career_work_archives (id, entity_type, entity_id, archived_at_ms) VALUES (?, 'goal', ?, 1)", arguments: [UUID().uuidString, entityID])
        }
        await #expect(throws: DatabaseError.self) {
            try await store.write { db in
                try db.execute(sql: "INSERT INTO career_work_archives (id, entity_type, entity_id, archived_at_ms) VALUES (?, 'goal', ?, 2)", arguments: [UUID().uuidString, entityID])
            }
        }
    }

    @Test func migrationIsIdempotentAndCreatesAllDomainTables() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let store = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let tables = try await store.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
        }
        let expected = ["profile", "conversations", "messages", "goals", "milestones", "actions", "evidence", "memory_items", "memory_sources", "sync_devices", "field_versions", "conflicts", "outbox", "inbox_quarantine", "tombstones", "sync_state", "vault_metadata", "snapshot_manifests", "migration_state", "voice_turns", "audio_cleanup_queue", "conversation_drafts", "message_revisions", "career_work_events", "career_work_archives", "evidence_provenance", "career_work_proposal_receipts", "capability_states", "weekly_placements", "work_events", "insights", "insight_sources", "insight_revisions", "action_checklist_items", "action_events", "action_evidence_links"]
        for name in expected { #expect(tables.contains(name)) }
        try await store.write { db in
            try db.execute(sql: "INSERT INTO profile (id, display_name, updated_at_ms) VALUES (?, ?, ?)", arguments: [UUID().uuidString, "preserved", 123])
        }
        let reopened = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let state = try await reopened.read { db in
            (try Int.fetchOne(db, sql: "PRAGMA user_version"), try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM profile"), try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM grdb_migrations"))
        }
        #expect(state.0 == 8)
        #expect(state.1 == 1)
#expect(state.2 == 8)
        #expect(!tables.contains("recordings"))
    }

    @Test func interruptedMigrationRollsBackAllSchemaChanges() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let queue = try fixture.makeKeyedQueue()
        #expect(throws: StorageError.migrationFailed) {
            try TaisaMigrator.migrate(queue, from: 0) { db in
                try TaisaSchema.createVersion1(in: db)
                throw MigrationInterruption.injected
            }
        }
        let state = try await queue.read { db in
            (try Int.fetchOne(db, sql: "PRAGMA user_version"), try String.fetchOne(db, sql: "SELECT name FROM sqlite_master WHERE name = 'profile'"), try String.fetchOne(db, sql: "SELECT name FROM sqlite_master WHERE name = 'goals'"))
        }
        #expect(state.0 == 0)
        #expect(state.1 == nil)
        #expect(state.2 == nil)
    }

    @Test func existingVersionOneStoreMigratesForwardWithoutLosingData() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let queue = try fixture.makeKeyedQueue()
        var legacy = DatabaseMigrator()
        legacy.registerMigration("v1", foreignKeyChecks: .immediate) { db in
            try TaisaSchema.createVersion1(in: db)
            try db.execute(
                sql: "INSERT INTO migration_state (version, applied_at_ms) VALUES (1, 1)"
            )
            try db.execute(sql: "PRAGMA user_version = 1")
        }
        try legacy.migrate(queue)
        try await queue.write { db in
            try db.execute(
                sql: "INSERT INTO profile (id, display_name, updated_at_ms) VALUES (?, 'preserved-v1', 1)",
                arguments: ["00000000-0000-0000-0000-000000000401"]
            )
        }
        try queue.close()

        let store = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let state = try await store.read { db in
            (
                try Int.fetchOne(db, sql: "PRAGMA user_version"),
                try String.fetchOne(db, sql: "SELECT display_name FROM profile"),
                try db.tableExists("voice_turns"),
                try Int.fetchAll(db, sql: "SELECT version FROM migration_state ORDER BY version")
            )
        }
        #expect(state.0 == 8)
        #expect(state.1 == "preserved-v1")
        #expect(state.2)
#expect(state.3 == [1, 2, 3, 4, 5, 6, 7, 8])
    }

    @Test func existingVersionTwoStoreMigratesWithoutInventingDraftsOrRevisions() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let queue = try fixture.makeKeyedQueue()
        var legacy = DatabaseMigrator()
        legacy.registerMigration("v1", foreignKeyChecks: .immediate) { db in
            try TaisaSchema.createVersion1(in: db)
            try db.execute(sql: "INSERT INTO migration_state (version, applied_at_ms) VALUES (1, 1)")
            try db.execute(sql: "PRAGMA user_version = 1")
        }
        legacy.registerMigration("v2", foreignKeyChecks: .immediate) { db in
            try TaisaSchema.createVersion2(in: db)
            try db.execute(sql: "INSERT INTO migration_state (version, applied_at_ms) VALUES (2, 2)")
            try db.execute(sql: "PRAGMA user_version = 2")
        }
        try legacy.migrate(queue)
        try queue.close()

        let store = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let state = try await store.read { db in
            (
                try Int.fetchOne(db, sql: "PRAGMA user_version"),
                try Int.fetchOne(db, sql: "SELECT count(*) FROM conversation_drafts"),
                try Int.fetchOne(db, sql: "SELECT count(*) FROM message_revisions"),
                try String.fetchOne(db, sql: "SELECT lifecycle FROM conversations LIMIT 1")
            )
        }
        #expect(state.0 == 8)
        #expect(state.1 == 0)
        #expect(state.2 == 0)
        #expect(state.3 == nil)
    }

    @Test func interruptedVersionFiveMigrationLeavesVersionFourAndUserDataUnchanged() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let queue = try fixture.makeKeyedQueue()
        var legacy = DatabaseMigrator()
        for entry in TaisaSchema.migrationLedger.prefix(4) {
            legacy.registerMigration(entry.identifier, foreignKeyChecks: .immediate) { db in
                switch entry.version {
                case 1: try TaisaSchema.createVersion1(in: db)
                case 2: try TaisaSchema.createVersion2(in: db)
                case 3: try TaisaSchema.createVersion3(in: db)
                case 4: try TaisaSchema.createVersion4(in: db)
                default: throw MigrationInterruption.injected
                }
                try db.execute(sql: "INSERT INTO migration_state (version, applied_at_ms) VALUES (?, ?)", arguments: [entry.version, entry.version])
                try db.execute(sql: "PRAGMA user_version = \(entry.version)")
            }
        }
        try legacy.migrate(queue)
        let goalID = UUID().uuidString
        try await queue.write { db in
            try db.execute(
                sql: "INSERT INTO goals (id, title, status, created_at_ms, updated_at_ms) VALUES (?, 'Preserve me', 'active', 1, 1)",
                arguments: [goalID]
            )
        }

        #expect(throws: StorageError.migrationFailed) {
            try TaisaMigrator.migrate(queue, from: 4, createVersion5: { db in
                try TaisaSchema.createVersion5(in: db)
                throw MigrationInterruption.injected
            })
        }
        let state = try await queue.read { db in
            (
                try Int.fetchOne(db, sql: "PRAGMA user_version"),
                try String.fetchOne(db, sql: "SELECT title FROM goals WHERE id = ?", arguments: [goalID]),
                try db.tableExists("weekly_placements"),
                try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
            )
        }
        #expect(state.0 == 4)
        #expect(state.1 == "Preserve me")
        #expect(!state.2)
        #expect(state.3 == ["v1", "v2", "v3", "v4"])
    }

    @Test func interruptedVersionSixMigrationLeavesVersionFiveAndRelationshipsUnchanged() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let queue = try fixture.makeKeyedQueue()
        var legacy = DatabaseMigrator()
        for entry in TaisaSchema.migrationLedger.prefix(5) {
            legacy.registerMigration(entry.identifier, foreignKeyChecks: .immediate) { db in
                switch entry.version {
                case 1: try TaisaSchema.createVersion1(in: db)
                case 2: try TaisaSchema.createVersion2(in: db)
                case 3: try TaisaSchema.createVersion3(in: db)
                case 4: try TaisaSchema.createVersion4(in: db)
                case 5: try TaisaSchema.createVersion5(in: db)
                default: throw MigrationInterruption.injected
                }
                try db.execute(
                    sql: "INSERT INTO migration_state (version, applied_at_ms) VALUES (?, ?)",
                    arguments: [entry.version, entry.version]
                )
                try db.execute(sql: "PRAGMA user_version = \(entry.version)")
            }
        }
        try legacy.migrate(queue)
        let goalID = UUID().uuidString
        let actionID = UUID().uuidString
        try await queue.write { db in
            try db.execute(
                sql: "INSERT INTO goals (id, title, status, created_at_ms, updated_at_ms) VALUES (?, 'Preserve me', 'active', 1, 1)",
                arguments: [goalID]
            )
            try db.execute(
                sql: "INSERT INTO actions (id, goal_id, title, status, created_at_ms, updated_at_ms) VALUES (?, ?, 'Still linked', 'open', 1, 1)",
                arguments: [actionID, goalID]
            )
        }

        #expect(throws: StorageError.migrationFailed) {
            try TaisaMigrator.migrate(queue, from: 5, createVersion6: { db in
                try TaisaSchema.createVersion6(in: db)
                throw MigrationInterruption.injected
            })
        }
        let state = try await queue.read { db in
            (
                try Int.fetchOne(db, sql: "PRAGMA user_version"),
                try String.fetchOne(db, sql: "SELECT title FROM goals WHERE id = ?", arguments: [goalID]),
                try String.fetchOne(db, sql: "SELECT title FROM actions WHERE id = ? AND goal_id = ?", arguments: [actionID, goalID]),
                try db.tableExists("goals_v6"),
                try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier"),
                try Int.fetchOne(db, sql: "SELECT count(*) FROM pragma_foreign_key_check")
            )
        }
        #expect(state.0 == 5)
        #expect(state.1 == "Preserve me")
        #expect(state.2 == "Still linked")
        #expect(!state.3)
        #expect(state.4 == ["v1", "v2", "v3", "v4", "v5"])
        #expect(state.5 == 0)
    }

    @Test func futureSchemaIsRejectedWithoutMutation() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let queue = try fixture.makeKeyedQueue()
        try await queue.write { db in try db.execute(sql: "PRAGMA user_version = 99") }
        let before = try Data(contentsOf: fixture.url)
        await #expect(throws: StorageError.unsupportedSchemaVersion(99)) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
        #expect(try Data(contentsOf: fixture.url) == before)
    }

    @Test func oneMutationCanVersionTwoFields() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let store = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let entity = UUID().uuidString
        let device = UUID().uuidString
        let titleVersion = UUID().uuidString
        let detailVersion = UUID().uuidString
        try await store.write { db in
            try db.execute(
                sql: "INSERT INTO field_versions (id, entity_type, entity_id, field_name, version_id, device_id, device_counter, updated_at_ms) VALUES (?, 'goal', ?, 'title', ?, ?, 1, 100)",
                arguments: [UUID().uuidString, entity, titleVersion, device]
            )
            try db.execute(
                sql: "INSERT INTO field_versions (id, entity_type, entity_id, field_name, version_id, device_id, device_counter, updated_at_ms) VALUES (?, 'goal', ?, 'detail', ?, ?, 1, 100)",
                arguments: [UUID().uuidString, entity, detailVersion, device]
            )
        }
        let count = try await store.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM field_versions") }
        #expect(count == 2)
    }

    @Test func existingOrphanRowIsRejectedWithoutRepair() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue(foreignKeysEnabled: false)
        try await raw.write { db in
            try db.execute(
                sql: "INSERT INTO messages (id, conversation_id, role, body, created_at_ms) VALUES (?, ?, 'user', 'orphan', 1)",
                arguments: [UUID().uuidString, UUID().uuidString]
            )
        }
        let before = try fixture.fileSnapshot()
        await #expect(throws: StorageError.integrityFailed) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
        #expect(try fixture.fileSnapshot() == before)
        #expect(try await fixture.keys.loadKey() == fixture.key)
        let violations = try await raw.read { db in try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").count }
        #expect(violations == 1)
    }

    @Test func existingCheckConstraintViolationIsRejected() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue()
        try await raw.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA ignore_check_constraints = ON")
            try db.execute(
                sql: "INSERT INTO goals (id, title, status, created_at_ms, updated_at_ms) VALUES (?, 'bad', 'invalid', 1, 1)",
                arguments: [UUID().uuidString]
            )
            try db.execute(sql: "PRAGMA ignore_check_constraints = OFF")
        }
        let invalidStatus = try await raw.read { db in
            try String.fetchOne(db, sql: "SELECT status FROM goals LIMIT 1")
        }
        #expect(invalidStatus == "invalid")
        let before = try fixture.fileSnapshot()
        await #expect(throws: StorageError.integrityFailed) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
        #expect(try fixture.fileSnapshot() == before)
    }

    @Test func missingRequiredTableIsRejectedWithoutRepair() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue()
        try await raw.write { db in try db.execute(sql: "DROP TABLE messages") }
        let before = try fixture.fileSnapshot()
        await #expect(throws: StorageError.schemaMismatch) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
        #expect(try fixture.fileSnapshot() == before)
        #expect(try await fixture.keys.loadKey() == fixture.key)
        #expect(try await raw.read { db in try !db.tableExists("messages") })
    }

    @Test func missingEssentialColumnIsRejected() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue()
        try await raw.write { db in
            try db.execute(sql: "ALTER TABLE profile RENAME COLUMN headline TO obsolete_headline")
        }
        await #expect(throws: StorageError.schemaMismatch) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
    }

    @Test func mismatchedVersionMarkersAreRejected() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue()
        try await raw.write { db in try db.execute(sql: "PRAGMA user_version = 0") }
        let before = try fixture.fileSnapshot()
        await #expect(throws: StorageError.schemaMismatch) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
        #expect(try fixture.fileSnapshot() == before)
    }

    @Test func missingMigrationStateIsRejected() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue()
        try await raw.write { db in try db.execute(sql: "DELETE FROM migration_state") }
        await #expect(throws: StorageError.schemaMismatch) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
    }

    @Test func unknownMigrationIdentifierIsRejectedWithoutRepair() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue()
        try await raw.write { db in try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v99')") }
        let before = try fixture.fileSnapshot()
        await #expect(throws: StorageError.unsupportedMigration) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
        #expect(try fixture.fileSnapshot() == before)
    }

    @Test func missingRequiredForeignKeyIsRejected() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue(foreignKeysEnabled: false)
        try await raw.write { db in
            try db.execute(sql: "DROP TABLE messages")
            try db.execute(sql: """
                CREATE TABLE messages (
                    id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
                    conversation_id TEXT NOT NULL,
                    role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
                    body TEXT NOT NULL,
                    created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0)
                )
                """)
            try db.execute(sql: "CREATE INDEX messages_by_conversation ON messages(conversation_id, created_at_ms)")
        }
        await #expect(throws: StorageError.schemaMismatch) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
    }

    @Test func missingPrimaryKeyIsRejected() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue()
        try await raw.write { db in
            try db.execute(sql: "DROP TABLE profile")
            try db.execute(sql: """
                CREATE TABLE profile (
                    id TEXT NOT NULL CHECK (length(id) = 36),
                    display_name TEXT NOT NULL DEFAULT '',
                    headline TEXT NOT NULL DEFAULT '',
                    biography TEXT NOT NULL DEFAULT '',
                    updated_at_ms INTEGER NOT NULL CHECK (updated_at_ms >= 0)
                )
                """)
        }
        await #expect(throws: StorageError.schemaMismatch) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
    }

    @Test func missingIdempotencyUniquenessIsRejected() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue()
        try await raw.write { db in
            try db.execute(sql: "DROP TABLE outbox")
            try db.execute(sql: """
                CREATE TABLE outbox (
                    id TEXT PRIMARY KEY NOT NULL CHECK (length(id) = 36),
                    mutation_id TEXT NOT NULL CHECK (length(mutation_id) = 36),
                    entity_type TEXT NOT NULL,
                    entity_id TEXT NOT NULL CHECK (length(entity_id) = 36),
                    payload BLOB NOT NULL,
                    status TEXT NOT NULL CHECK (status IN ('pending', 'retrying', 'acknowledged')),
                    retry_category TEXT,
                    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
                    created_at_ms INTEGER NOT NULL CHECK (created_at_ms >= 0),
                    acknowledged_at_ms INTEGER CHECK (acknowledged_at_ms >= created_at_ms)
                )
                """)
            try db.execute(sql: "CREATE INDEX outbox_pending ON outbox(status, created_at_ms)")
        }
        await #expect(throws: StorageError.schemaMismatch) {
            try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        }
    }

    @Test func unknownVersionZeroSchemaIsRejectedBeforeMetadataCreation() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let raw = try fixture.makeKeyedQueue()
        try await raw.write { db in
            try db.execute(sql: "CREATE TABLE unrelated_data (id TEXT PRIMARY KEY)")
            try db.execute(sql: "INSERT INTO unrelated_data (id) VALUES ('private')")
        }
        let restarted = try fixture.restartCopy()
        let before = try fixture.fileSnapshot(at: restarted)
        await #expect(throws: StorageError.schemaMismatch) {
            try await TaisaStore.open(at: restarted, keyStore: fixture.keys)
        }
        #expect(try fixture.fileSnapshot(at: restarted) == before)
        #expect(try await fixture.keys.loadKey() == fixture.key)
        let check = try fixture.makeKeyedQueue(at: restarted, readonly: true)
        #expect(try await check.read { db in try !db.tableExists("grdb_migrations") })
        #expect(try await check.read { db in try !db.tableExists("profile") })
    }

    @Test func sqliteXdataVersionZeroSchemaIsRejectedBeforeMetadataCreation() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        let raw = try fixture.makeKeyedQueue()
        try await raw.write { db in
            try db.execute(sql: "CREATE TABLE sqliteXdata (id TEXT PRIMARY KEY)")
            try db.execute(sql: "INSERT INTO sqliteXdata (id) VALUES ('private')")
        }
        let restarted = try fixture.restartCopy()
        let before = try fixture.fileSnapshot(at: restarted)
        await #expect(throws: StorageError.schemaMismatch) {
            try await TaisaStore.open(at: restarted, keyStore: fixture.keys)
        }
        #expect(try fixture.fileSnapshot(at: restarted) == before)
        #expect(try await fixture.keys.loadKey() == fixture.key)
        let check = try fixture.makeKeyedQueue(at: restarted, readonly: true)
        #expect(try await check.read { db in try !db.tableExists("grdb_migrations") })
        #expect(try await check.read { db in try !db.tableExists("profile") })
    }

    @Test func emptyExistingVersionZeroSchemaInitializes() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try fixture.makeKeyedQueue()
        let restarted = try fixture.restartCopy()
        let store = try await TaisaStore.open(at: restarted, keyStore: fixture.keys)
        #expect(try await store.read { db in try db.tableExists("profile") })
#expect(try await store.read { db in try Int.fetchOne(db, sql: "PRAGMA user_version") } == 8)
        #expect(try await fixture.keys.loadKey() == fixture.key)
    }

    @Test func schemaChangeAfterSnapshotIsRejectedWithoutTouchingOriginal() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let restarted = try fixture.restartCopy()
        let otherWriter = try fixture.makeKeyedQueue(at: restarted)
        let mutation = MigrationSnapshotRecorder()
        await #expect(throws: StorageError.integrityFailed) {
            try await TaisaStore.open(
                at: restarted,
                keyStore: fixture.keys,
                afterValidation: {
                    try await otherWriter.write { db in try db.execute(sql: "DROP TABLE messages") }
                    try await mutation.record(fixture.fileSnapshot(at: restarted))
                }
            )
        }
        let afterMutation = await mutation.snapshot
        #expect(afterMutation != nil)
        #expect(try fixture.fileSnapshot(at: restarted) == afterMutation)
        #expect(try await fixture.keys.loadKey() == fixture.key)
        #expect(try await otherWriter.read { db in try !db.tableExists("messages") })
    }

    @Test func schemaChangeAfterGenerationCheckCannotBePublished() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let restarted = try fixture.restartCopy()
        let otherWriter = try fixture.makeKeyedQueue(at: restarted)
        let mutation = MigrationSnapshotRecorder()
        await #expect(throws: StorageError.integrityFailed) {
            try await TaisaStore.open(
                at: restarted,
                keyStore: fixture.keys,
                afterValidation: {},
                afterGeneration: {
                    try await otherWriter.write { db in try db.execute(sql: "DROP TABLE messages") }
                    try otherWriter.close()
                    try await mutation.record(fixture.fileSnapshot(at: restarted))
                }
            )
        }
        let afterMutation = await mutation.snapshot
        #expect(afterMutation?.durableBytes["-wal"]?.isEmpty == false)
        #expect(try fixture.fileSnapshot(at: restarted) == afterMutation)
        #expect(try await fixture.keys.loadKey() == fixture.key)
        let check = try fixture.makeKeyedQueue(at: restarted, readonly: true)
        #expect(try await check.read { db in try !db.tableExists("messages") })
    }

    @Test func soleConnectionOrphanWalIsRejectedWithoutCheckpoint() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue(foreignKeysEnabled: false)
        try await raw.write { db in
            try db.execute(
                sql: "INSERT INTO messages (id, conversation_id, role, body, created_at_ms) VALUES (?, ?, 'user', 'orphan', 1)",
                arguments: [UUID().uuidString, UUID().uuidString]
            )
        }
        let restarted = try fixture.restartCopy()
        let before = try fixture.fileSnapshot(at: restarted)
        #expect(before.durableBytes["-wal"]?.isEmpty == false)
        await #expect(throws: StorageError.integrityFailed) {
            try await TaisaStore.open(at: restarted, keyStore: fixture.keys)
        }
        #expect(try fixture.fileSnapshot(at: restarted) == before)
        #expect(try await fixture.keys.loadKey() == fixture.key)
    }

    @Test func soleConnectionDamagedSchemaWalIsRejectedWithoutCheckpoint() async throws {
        let fixture = try MigrationFixture()
        defer { fixture.remove() }
        _ = try await TaisaStore.open(at: fixture.url, keyStore: fixture.keys)
        let raw = try fixture.makeKeyedQueue()
        try await raw.write { db in try db.execute(sql: "DROP TABLE messages") }
        let restarted = try fixture.restartCopy()
        let before = try fixture.fileSnapshot(at: restarted)
        #expect(before.durableBytes["-wal"]?.isEmpty == false)
        await #expect(throws: StorageError.schemaMismatch) {
            try await TaisaStore.open(at: restarted, keyStore: fixture.keys)
        }
        #expect(try fixture.fileSnapshot(at: restarted) == before)
        #expect(try await fixture.keys.loadKey() == fixture.key)
    }
}

private struct MigrationFixture {
    let directory: URL
    let url: URL
    let key = Data((0..<32).map(UInt8.init))
    let keys: FixedDatabaseKeyStore

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("migration.sqlite")
        keys = FixedDatabaseKeyStore(key: key)
    }

    func makeKeyedQueue(
        at target: URL? = nil,
        foreignKeysEnabled: Bool = true,
        readonly: Bool = false
    ) throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = foreignKeysEnabled
        configuration.readonly = readonly
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA key = \"x'000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f'\"")
        }
        return try DatabaseQueue(path: (target ?? url).path, configuration: configuration)
    }

    func restartCopy() throws -> URL {
        let restarted = directory.appendingPathComponent(UUID().uuidString + ".sqlite")
        // Source writers are idle while these files are copied; the copied
        // target has no open connection and retains its pending WAL.
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(
                    at: source,
                    to: URL(fileURLWithPath: restarted.path + suffix)
                )
            }
        }
        return restarted
    }

    func fileSnapshot(at target: URL? = nil) throws -> MigrationFileSnapshot {
        var durableBytes: [String: Data] = [:]
        var fileNumbers: [String: UInt64] = [:]
        for suffix in ["", "-wal", "-shm"] {
            let path = URL(fileURLWithPath: (target ?? url).path + suffix)
            if FileManager.default.fileExists(atPath: path.path) {
                let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
                guard let number = attributes[.systemFileNumber] as? NSNumber else {
                    throw CocoaError(.fileReadUnknown)
                }
                fileNumbers[suffix] = number.uint64Value
                // SQLite changes -shm reader slots even for a rejected open.
                if suffix != "-shm" { durableBytes[suffix] = try Data(contentsOf: path) }
            }
        }
        return MigrationFileSnapshot(durableBytes: durableBytes, fileNumbers: fileNumbers)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private struct MigrationFileSnapshot: Equatable, Sendable {
    let durableBytes: [String: Data]
    let fileNumbers: [String: UInt64]
}

private actor MigrationSnapshotRecorder {
    private(set) var snapshot: MigrationFileSnapshot?
    func record(_ value: MigrationFileSnapshot) { snapshot = value }
}

private enum MigrationInterruption: Error { case injected }

private actor FixedDatabaseKeyStore: DatabaseKeyStore {
    let key: Data
    init(key: Data) { self.key = key }
    func loadKey() async throws -> Data? { key }
    func saveKey(_ key: Data) async throws { Issue.record("Existing fixture key must not be replaced") }
}

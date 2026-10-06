import Foundation
import Testing
import TaisaStorage
import TaisaRecovery
import TaisaSecurity
@testable import TaisaPersonal

@Suite struct PersonalDeviceQATests {
    @Test func disabledLaunchDoesNotOpenOrSeedStore() async throws {
        let fixture = try QAFixture()
        defer { fixture.remove() }
        #expect(PersonalDeviceQA(backend: fixture.backend, arguments: []) == nil)
        #expect(PersonalDeviceQA(backend: fixture.backend, arguments: ["--taisa-personal-device-qa=yes"]) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.storeURL.path))
    }

    @Test func inspectionNeverSeedsAndRepeatedCreationSurvivesReopenWithoutDuplicates() async throws {
        let fixture = try QAFixture()
        defer { fixture.remove() }
        let qa = try #require(PersonalDeviceQA(backend: fixture.backend, arguments: ["--taisa-personal-device-qa"]))
        let empty = try await qa.inspect()
        #expect(empty.canaryCount == 0)
        #expect(empty.conversationCount == 0)
        #expect(empty.hash == nil)
        async let initialCreate = qa.createCanary()
        async let competingCreate = qa.createCanary()
        let created = try await initialCreate
        #expect(try await competingCreate == created)
        #expect(created.canaryCount == 1)
        #expect(created.conversationCount == 1)
        #expect(created.hash == "ccec885e1c7c69364095415e88d75bb0736224accdb5dad95d9905ba47898d64")
        #expect(try await qa.createCanary() == created)
        async let first = qa.createCanary()
        async let second = qa.createCanary()
        #expect(try await first == created)
        #expect(try await second == created)
        let reopened = try #require(PersonalDeviceQA(backend: fixture.backend, arguments: ["--taisa-personal-device-qa"]))
        #expect(try await reopened.inspect() == created)
        let store = try await fixture.backend.openStore()
        #expect(try await ChangeJournal(store: store).pending(limit: 10).count == 1)
        let bytes = try Data(contentsOf: fixture.storeURL)
        #expect(!bytes.contains(Data("Taisa public device QA canary v1".utf8)))
    }

    @Test func realBackupRestoreRetainsEvidenceWithoutReceiverSeeding() async throws {
        let source = try QAFixture(), receiver = try QAFixture()
        defer { source.remove(); receiver.remove() }
        let sourceQA = try #require(PersonalDeviceQA(backend: source.backend, arguments: ["--taisa-personal-device-qa"]))
        let receiverQA = try #require(PersonalDeviceQA(backend: receiver.backend, arguments: ["--taisa-personal-device-qa"]))
        let expected = try await sourceQA.createCanary()
        #expect(try await receiverQA.inspect().canaryCount == 0)
        let key = try RecoveryKey.generate()
        let document = try await source.backend.createBackup(key: key)
        #expect(!((try Data(contentsOf: document.shareURL)).contains(Data("Taisa public device QA canary v1".utf8))))
        try await receiver.backend.copyImport(document.shareURL)
        try await receiver.backend.validate(key: key)
        try await receiver.backend.promote(confirmed: true)
        #expect(try await receiverQA.inspect() == expected)
        #expect(try await receiverQA.createCanary() == expected)
    }

    @Test func conflictingContentIsNeitherExposedHashedNorOverwritten() async throws {
        let fixture = try QAFixture()
        defer { fixture.remove() }
        let store = try await fixture.backend.openStore()
        let repository = ConversationRepository(store: store)
        let record = ConversationRecord(id: "00000000-0000-4000-8000-000000000601", title: "PRIVATE-QA-CONFLICT-DO-NOT-LOG", createdAtMS: 0, updatedAtMS: 0)
        try await repository.create(record, context: .init(id: UUID().uuidString, deviceID: UUID().uuidString, timestamp: 0))
        let qa = try #require(PersonalDeviceQA(backend: fixture.backend, arguments: ["--taisa-personal-device-qa"]))
        let evidence = try await qa.inspect()
        #expect(evidence.canaryCount == 0)
        #expect(evidence.hash == nil)
        await #expect(throws: PersonalDeviceQA.Failure.self) { try await qa.createCanary() }
        #expect(try await repository.get(id: record.id) == record)
    }
}

private actor QAKeys: DatabaseKeyStore {
    private var key: Data?
    func loadKey() -> Data? { key }
    func saveKey(_ value: Data) { key = value }
}
private struct QAAudio: AudioExportGuard {
    func assertNoPendingAudioReferences() async throws {}
}
private struct QAFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let keys = QAKeys()
    let backend: PersonalRecoveryBackend
    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.complete])
        backend = .init(storeURL: root.appendingPathComponent("active.sqlite"), keyStore: keys,
                        installationID: UUID(), transferRoot: root.appendingPathComponent("transfers"), audioGuard: QAAudio())
    }
    var storeURL: URL { root.appendingPathComponent("active.sqlite") }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

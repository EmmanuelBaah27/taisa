import SwiftUI
import UniformTypeIdentifiers
import TaisaRecovery
import TaisaSecurity

extension UTType {
    static let taisaBackup = UTType(exportedAs: "com.taisa.encrypted-backup", conformingTo: .data)
}

/// Export-only: an arbitrary selected file can never become an export document.
struct TaisaBackupDocument: FileDocument, Sendable {
    static var readableContentTypes: [UTType] { [.taisaBackup] }
    private let encryptedBytes: Data
    let shareURL: URL

    init(verified receipt: SnapshotReceipt, recoveryKey: RecoveryKey) throws {
        // The backend retains its private directory until the system finishes.
        guard try PortableArchive.verify(at: receipt.archiveURL, recoveryKey: recoveryKey) == receipt.manifest else {
            throw SnapshotError.authenticationFailed
        }
        encryptedBytes = try Data(contentsOf: receipt.archiveURL)
        shareURL = receipt.archiveURL
    }

    init(configuration: ReadConfiguration) throws { throw SnapshotError.malformedArchive }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: encryptedBytes)
    }
}

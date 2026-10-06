import SwiftUI
import UniformTypeIdentifiers
import TaisaRecovery
import TaisaSecurity

extension UTType {
    static let taisaBackup = UTType(exportedAs: "com.taisa.encrypted-backup", conformingTo: .data)
}

/// Export-only: an arbitrary selected file can never become an export document.
struct TaisaBackupDocument: Sendable {
    let shareURL: URL

    init(verified receipt: SnapshotReceipt, recoveryKey: RecoveryKey) throws {
        // The backend retains its private directory until the system finishes.
        guard try PortableArchive.verify(at: receipt.archiveURL, recoveryKey: recoveryKey) == receipt.manifest else {
            throw SnapshotError.authenticationFailed
        }
        shareURL = receipt.archiveURL
    }

    @MainActor func exportController(delegate: any UIDocumentPickerDelegate) -> UIDocumentPickerViewController {
        // iOS 14+: the system copies from the verified file URL. No FileDocument,
        // Data representation, or regular-file wrapper buffers the archive.
        let picker = UIDocumentPickerViewController(forExporting: [shareURL], asCopy: true)
        picker.delegate = delegate
        return picker
    }
}

struct BackupFileExporter: UIViewControllerRepresentable {
    let document: TaisaBackupDocument
    let completion: @MainActor (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        document.exportController(delegate: context.coordinator)
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    @MainActor final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private var completion: ((Bool) -> Void)?
        init(completion: @escaping (Bool) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finish(!urls.isEmpty)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(false) }
        private func finish(_ success: Bool) {
            let callback = completion; completion = nil
            callback?(success)
        }
    }
}

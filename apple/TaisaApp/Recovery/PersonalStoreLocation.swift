import Foundation
import TaisaSecurity
import TaisaStorage

struct PersonalStoreLocation {
    let storeURL: URL
    let keyStore: any DatabaseKeyStore
    let installationID: UUID
    let transferRoot: URL

    static func live() throws -> PersonalStoreLocation {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Taisa", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.complete]
        )
        var protectedRoot = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedRoot.setResourceValues(values)

        let defaults = UserDefaults.standard
        let key = "taisa.personal.installation"
        let installationID = defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) ?? UUID()
        defaults.set(installationID.uuidString, forKey: key)

        return PersonalStoreLocation(
            storeURL: root.appendingPathComponent("taisa.sqlite"),
            keyStore: KeychainStore(),
            installationID: installationID,
            transferRoot: FileManager.default.temporaryDirectory.appendingPathComponent("TaisaTransfers")
        )
    }
}

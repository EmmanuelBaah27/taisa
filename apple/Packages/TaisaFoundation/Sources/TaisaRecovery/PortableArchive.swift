import CryptoKit
import Foundation
import Security
import TaisaSecurity

/// v1 wire format (integers are unsigned big-endian):
/// magic[8], version[4], archive UUID[16], salt[32], sealed-manifest length[4],
/// sealed manifest, then ordered (sealed length[4], AES-GCM combined) frames.
/// Each combined box is nonce[12] || ciphertext || tag[16]. Manifest JSON uses
/// sorted keys and milliseconds since Unix epoch. The full 64-byte prefix is
/// manifest AAD; frame AAD adds SHA256(canonical manifest), index and count.
public enum PortableArchive {
    public static let chunkSize = 1_048_576
    static let maximumManifestBytes = 65_536
    static let magic = Data("TAISABK1".utf8)

    public static func verify(
        at url: URL, recoveryKey: RecoveryKey,
        maximumPayloadBytes: Int64 = 1_073_741_824
    ) throws -> SnapshotManifest {
        do {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            let header = try readExactly(64, from: file)
            guard header.prefix(8) == magic else { throw SnapshotError.malformedArchive }
            guard integer(header.subdata(in: 8..<12)) == 1 else { throw SnapshotError.unsupportedVersion }
            let length = integer(header.subdata(in: 60..<64))
            guard length >= 28, length <= maximumManifestBytes else { throw SnapshotError.malformedArchive }
            let key = try recoveryKey.derivePortableBackupKey(salt: header.subdata(in: 28..<60), purpose: .frames)
            let manifestBox = try readExactly(length, from: file)
            let manifestData = try open(manifestBox, key: key, aad: header)
            let manifest: SnapshotManifest
            do { manifest = try decoder().decode(SnapshotManifest.self, from: manifestData) }
            catch { throw SnapshotError.malformedArchive }
            guard try canonical(manifest) == manifestData,
                  manifest.formatVersion == 1, manifest.schemaVersion > 0,
                  manifest.plaintextSHA256.count == 32,
                  manifest.plaintextByteCount > 0,
                  manifest.plaintextByteCount <= maximumPayloadBytes,
                  manifest.chunkCount > 0,
                  manifest.chunkCount <= Int(UInt32.max),
                  Int64(manifest.chunkCount) == (manifest.plaintextByteCount - 1) / Int64(chunkSize) + 1,
                  manifest.entityCounts.values.allSatisfy({ $0 >= 0 }) else {
                throw SnapshotError.malformedArchive
            }
            let digest = Data(SHA256.hash(data: manifestData))
            var seenNonces: Set<Data> = [Data(manifestBox.prefix(12))]
            var hash = SHA256()
            var total: Int64 = 0
            for index in 0..<manifest.chunkCount {
                try Task.checkCancellation()
                let expected = Int(min(Int64(chunkSize), manifest.plaintextByteCount - total))
                let size = integer(try readExactly(4, from: file))
                guard size == expected + 28 else { throw SnapshotError.malformedArchive }
                let box = try readExactly(size, from: file)
                guard seenNonces.insert(Data(box.prefix(12))).inserted else { throw SnapshotError.malformedArchive }
                let data = try open(box, key: key, aad: frameAAD(header: header, digest: digest, index: index, count: manifest.chunkCount))
                hash.update(data: data); total += Int64(data.count)
            }
            guard total == manifest.plaintextByteCount,
                  Data(hash.finalize()) == manifest.plaintextSHA256,
                  (try file.read(upToCount: 1) ?? Data()).isEmpty else {
                throw SnapshotError.authenticationFailed
            }
            return manifest
        } catch is CancellationError { throw CancellationError() }
        catch let error as SnapshotError { throw error }
        catch { throw SnapshotError.ioFailure }
    }

    static func write(database: URL, manifest: SnapshotManifest, salt: Data,
                      recoveryKey: RecoveryKey, to output: FileHandle) throws {
        let data = try canonical(manifest)
        guard data.count + 28 <= maximumManifestBytes else { throw SnapshotError.malformedArchive }
        var uuid = UUID().uuid
        let archiveID = withUnsafeBytes(of: &uuid) { Data($0) }
        let header = magic + u32(1) + archiveID + salt + u32(data.count + 28)
        let key = try recoveryKey.derivePortableBackupKey(salt: salt, purpose: .frames)
        var used = Set<Data>()
        func seal(_ data: Data, aad: Data) throws -> Data {
            var nonce: AES.GCM.Nonce
            repeat { nonce = AES.GCM.Nonce() } while !used.insert(nonce.withUnsafeBytes { Data($0) }).inserted
            guard let combined = try AES.GCM.seal(data, using: key, nonce: nonce, authenticating: aad).combined else {
                throw SnapshotError.authenticationFailed
            }
            return combined
        }
        try output.write(contentsOf: header)
        try output.write(contentsOf: seal(data, aad: header))
        let digest = Data(SHA256.hash(data: data))
        let input = try FileHandle(forReadingFrom: database)
        defer { try? input.close() }
        for index in 0..<manifest.chunkCount {
            try Task.checkCancellation()
            let data = try readExactly(Int(min(Int64(chunkSize), manifest.plaintextByteCount - Int64(index) * Int64(chunkSize))), from: input)
            let box = try seal(data, aad: frameAAD(header: header, digest: digest, index: index, count: manifest.chunkCount))
            try output.write(contentsOf: u32(box.count))
            try output.write(contentsOf: box)
        }
        guard (try input.read(upToCount: 1) ?? Data()).isEmpty else { throw SnapshotError.malformedArchive }
    }

    static func randomSalt() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw SnapshotError.ioFailure }
        return Data(bytes)
    }

    static func canonical(_ manifest: SnapshotManifest) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(manifest)
    }
    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
    private static func frameAAD(header: Data, digest: Data, index: Int, count: Int) -> Data {
        header + digest + u32(index) + u32(count)
    }
    private static func open(_ box: Data, key: SymmetricKey, aad: Data) throws -> Data {
        do { return try AES.GCM.open(AES.GCM.SealedBox(combined: box), using: key, authenticating: aad) }
        catch { throw SnapshotError.authenticationFailed }
    }
    private static func readExactly(_ count: Int, from file: FileHandle) throws -> Data {
        var result = Data()
        while result.count < count {
            guard let next = try file.read(upToCount: count - result.count), !next.isEmpty else { throw SnapshotError.malformedArchive }
            result.append(next)
        }
        return result
    }
    private static func integer(_ data: Data) -> Int { data.reduce(0) { ($0 << 8) | Int($1) } }
    private static func u32(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).bigEndian) { Data($0) } }
}

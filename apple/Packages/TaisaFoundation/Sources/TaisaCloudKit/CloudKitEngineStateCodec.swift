import CloudKit
import Foundation

enum CloudKitEngineStateCodec {
    static func encode(_ state: CKSyncEngine.State.Serialization) throws -> Data {
        try JSONEncoder().encode(state)
    }

    static func decode(_ data: Data?) throws -> CKSyncEngine.State.Serialization? {
        guard let data else { return nil }
        return try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }
}

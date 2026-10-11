import Foundation
import Testing
@testable import TaisaVoice

@Suite("Voice gateway credential store")
struct VoiceGatewayCredentialStoreTests {
    @Test("round trips a credential for its origin")
    func roundTrip() async throws {
        let store = InMemoryVoiceGatewayCredentialStore()
        let credential = try fixture(origin: "https://voice.example.com")

        try await store.save(credential)

        #expect(try await store.load(origin: credential.origin) == credential)
    }

    @Test("isolates credentials by normalized origin")
    func originIsolation() async throws {
        let store = InMemoryVoiceGatewayCredentialStore()
        let primary = try fixture(origin: "https://voice.example.com", token: "primary-secret")
        let secondary = try fixture(origin: "https://voice.example.net", token: "secondary-secret")

        try await store.save(primary)
        try await store.save(secondary)

        #expect(try await store.load(origin: primary.origin) == primary)
        #expect(try await store.load(origin: secondary.origin) == secondary)
    }

    @Test("replaces the credential for an existing origin")
    func replacement() async throws {
        let store = InMemoryVoiceGatewayCredentialStore()
        let original = try fixture(origin: "https://voice.example.com", id: "credential-1", token: "old-secret")
        let replacement = try fixture(origin: "https://voice.example.com", id: "credential-2", token: "new-secret")

        try await store.save(original)
        try await store.save(replacement)

        #expect(try await store.load(origin: original.origin) == replacement)
    }

    @Test("deletes only the credential for the requested origin")
    func deletion() async throws {
        let store = InMemoryVoiceGatewayCredentialStore()
        let deleted = try fixture(origin: "https://voice.example.com")
        let retained = try fixture(origin: "https://voice.example.net", token: "retained-secret")
        try await store.save(deleted)
        try await store.save(retained)

        try await store.delete(origin: deleted.origin)

        #expect(try await store.load(origin: deleted.origin) == nil)
        #expect(try await store.load(origin: retained.origin) == retained)
    }

    @Test("rejects malformed and unsupported persisted payloads")
    func malformedPayload() throws {
        #expect(throws: VoiceGatewayCredentialStoreError.invalidPersistedCredential) {
            _ = try VoiceGatewayCredentialCodec.decode(Data("not-json".utf8))
        }
        #expect(throws: VoiceGatewayCredentialStoreError.unsupportedPayloadVersion) {
            _ = try VoiceGatewayCredentialCodec.decode(Data("""
            {"version":2,"origin":"https://voice.example.com","credentialID":"credential-1","bearerToken":"secret"}
            """.utf8))
        }
    }

    @Test("diagnostics never expose the bearer token")
    func diagnosticRedaction() throws {
        let secret = "do-not-log-this-token"
        let credential = try fixture(origin: "https://voice.example.com", token: secret)

        #expect(!String(describing: credential).contains(secret))
        #expect(!String(reflecting: credential).contains(secret))
        #expect(!String(describing: VoiceGatewayCredentialStoreError.invalidPersistedCredential).contains(secret))
    }
}

private func fixture(
    origin: String,
    id: String = "credential-1",
    token: String = "bearer-secret"
) throws -> VoiceGatewayCredential {
    try VoiceGatewayCredential(
        origin: #require(URL(string: origin)),
        credentialID: id,
        bearerToken: token
    )
}

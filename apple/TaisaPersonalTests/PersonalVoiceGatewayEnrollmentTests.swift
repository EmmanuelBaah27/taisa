import Foundation
import Testing
import TaisaVoice
@testable import TaisaPersonal

@MainActor
@Suite("Personal voice gateway enrollment")
struct PersonalVoiceGatewayEnrollmentTests {
    @Test("blank gateway URL remains not configured")
    func blankURL() async {
        let model = PersonalVoiceSessionModel(
            gatewayURLString: "",
            enrollmentClient: EnrollmentStub(result: .failure(.serverUnavailable)),
            credentialStore: InMemoryVoiceGatewayCredentialStore(),
            runtimeStarter: { _ in Issue.record("Runtime must not start") }
        )

        await model.start()

        #expect(model.gatewayState == .notConfigured)
        #expect(model.status == "Configure an approved HTTPS Taisa voice gateway for this build.")
    }

    @Test("configured gateway without a credential requests enrollment")
    func enrollmentRequired() async {
        let model = PersonalVoiceSessionModel(
            gatewayURLString: "https://voice.example.com",
            enrollmentClient: EnrollmentStub(result: .failure(.serverUnavailable)),
            credentialStore: InMemoryVoiceGatewayCredentialStore(),
            runtimeStarter: { _ in Issue.record("Runtime must not start") }
        )

        await model.start()

        #expect(model.gatewayState == .enrollmentRequired)
        #expect(model.status == "Connect this device to the approved voice gateway.")
    }

    @Test("successful enrollment is stored before the runtime becomes ready")
    func successfulEnrollment() async throws {
        let origin = try #require(URL(string: "https://voice.example.com"))
        let credential = try VoiceGatewayCredential(
            origin: origin, credentialID: "credential-1", bearerToken: "opaque-token"
        )
        let store = InMemoryVoiceGatewayCredentialStore()
        let model = PersonalVoiceSessionModel(
            gatewayURLString: origin.absoluteString,
            enrollmentClient: EnrollmentStub(result: .success(credential)),
            credentialStore: store,
            runtimeStarter: { received in
                let stored = try await store.load(origin: origin)
                #expect(stored == received)
            }
        )
        await model.start()

        await model.connect(code: "one-time-code")

        #expect(model.gatewayState == .ready)
        #expect(model.status == "Ready")
    }

    @Test("invalid code never overwrites a valid credential")
    func invalidCodePreservesCredential() async throws {
        let origin = try #require(URL(string: "https://voice.example.com"))
        let existing = try VoiceGatewayCredential(
            origin: origin, credentialID: "credential-existing", bearerToken: "existing-token"
        )
        let store = InMemoryVoiceGatewayCredentialStore()
        try await store.save(existing)
        let model = PersonalVoiceSessionModel(
            gatewayURLString: origin.absoluteString,
            enrollmentClient: EnrollmentStub(result: .failure(.invalidOrExpiredCode)),
            credentialStore: store,
            runtimeStarter: { _ in }
        )
        await model.start()

        await model.connect(code: "wrong-code")

        #expect(try await store.load(origin: origin) == existing)
        #expect(model.gatewayState == .invalidOrExpiredCode)
    }

    @Test("rejected credentials return to re-enrollment")
    func rejectedCredential() async throws {
        let origin = try #require(URL(string: "https://voice.example.com"))
        let credential = try VoiceGatewayCredential(
            origin: origin, credentialID: "credential-1", bearerToken: "rejected-token"
        )
        let store = InMemoryVoiceGatewayCredentialStore()
        try await store.save(credential)
        let model = PersonalVoiceSessionModel(
            gatewayURLString: origin.absoluteString,
            enrollmentClient: EnrollmentStub(result: .success(credential)),
            credentialStore: store,
            runtimeStarter: { _ in }
        )
        await model.start()

        await model.credentialWasRejected()

        #expect(model.gatewayState == .reEnrollmentRequired)
        #expect(try await store.load(origin: origin) == nil)
    }

    @Test("status text never exposes enrollment or bearer secrets")
    func statusRedaction() async throws {
        let secret = "do-not-display-this-secret"
        let model = PersonalVoiceSessionModel(
            gatewayURLString: "https://voice.example.com",
            enrollmentClient: EnrollmentStub(result: .failure(.serverUnavailable), privateDetail: secret),
            credentialStore: InMemoryVoiceGatewayCredentialStore(),
            runtimeStarter: { _ in }
        )
        await model.start()

        await model.connect(code: secret)

        #expect(!model.status.contains(secret))
        #expect(model.gatewayState == .enrollmentRequired)
    }
}

private actor EnrollmentStub: VoiceGatewayEnrolling {
    let result: Result<VoiceGatewayCredential, VoiceGatewayEnrollmentError>
    let privateDetail: String?

    init(
        result: Result<VoiceGatewayCredential, VoiceGatewayEnrollmentError>,
        privateDetail: String? = nil
    ) {
        self.result = result
        self.privateDetail = privateDetail
    }

    func enroll(baseURL: URL, code: String) async throws -> VoiceGatewayCredential {
        if let privateDetail {
            throw NSError(domain: "PrivateEnrollment", code: 1, userInfo: [
                NSLocalizedDescriptionKey: privateDetail,
            ])
        }
        return try result.get()
    }
}

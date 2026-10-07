import Foundation
#if TAISA_HAS_CREDENTIAL_DATA_MANAGER_SDK && os(iOS)
import AuthenticationServices
#endif

public enum ManualSaveReason: Equatable, Sendable {
    case sdkOrDomainUnavailable
    case userDeclined
    case saveFailed
}

public enum PasswordSaveResult: Equatable, Sendable {
    case savedToPasswords
    case manualSaveRequired(ManualSaveReason)
}

public protocol PasswordsSaving: Sendable {
    func save(recoveryKey: RecoveryKey) async throws -> PasswordSaveResult
}

/// Programmatic saving requires both a supporting SDK and an approved owned
/// Web Credentials domain. Neither is configured in the present build.
public struct SystemPasswordsSaver: PasswordsSaving {
    #if TAISA_HAS_CREDENTIAL_DATA_MANAGER_SDK
    private let approvedOwnedDomain: String?

    public init() { approvedOwnedDomain = nil }

    // Set only after the Task 7 associated-domain approval and entitlement check.
    init(approvedOwnedDomain: String) { self.approvedOwnedDomain = approvedOwnedDomain }
    #else
    public init() {}
    #endif

    public func save(recoveryKey: RecoveryKey) async throws -> PasswordSaveResult {
        #if TAISA_HAS_CREDENTIAL_DATA_MANAGER_SDK && os(iOS)
        if #available(iOS 26, *), let approvedOwnedDomain {
            return await saveWithSupportedSDK(recoveryKey, domain: approvedOwnedDomain)
        }
        #endif
        return .manualSaveRequired(.sdkOrDomainUnavailable)
    }

    #if TAISA_HAS_CREDENTIAL_DATA_MANAGER_SDK && os(iOS)
    @available(iOS 26, *)
    private func saveWithSupportedSDK(_ recoveryKey: RecoveryKey, domain: String) async -> PasswordSaveResult {
        // This branch is intentionally not typechecked by Xcode 26.1: that SDK does
        // not declare ASCredentialDataManager/ASAutoFillURLScope. Revalidate the
        // signatures and enable this flag only with a supporting SDK and domain.
        guard let url = URL(string: "https://\(domain)"),
              url.host == domain,
              url.path.isEmpty || url.path == "/",
              url.query == nil, url.fragment == nil
        else { return .manualSaveRequired(.sdkOrDomainUnavailable) }
        let credential = ASPasswordCredential(user: "Taisa Recovery", password: recoveryKey.formatted)
        do {
            try await ASCredentialDataManager().save(
                password: credential,
                for: ASAutoFillURLScope(url: url),
                title: "Taisa Recovery"
            )
            return .savedToPasswords
        } catch {
            return .manualSaveRequired(.saveFailed)
        }
    }
    #endif
}

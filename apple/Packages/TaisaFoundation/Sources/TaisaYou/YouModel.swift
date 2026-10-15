import Observation
import TaisaStorage

public enum YouIssue: Sendable, Equatable {
    case storageUnavailable, recoveryRequired, invalidInput, conflict

    public var guidance: String {
        switch self {
        case .storageUnavailable: "Your encrypted information could not be loaded. Try again."
        case .recoveryRequired: "Taisa could not safely open your encrypted data. Open backup and recovery."
        case .invalidInput: "Review the highlighted information and try again."
        case .conflict: "This information changed since you opened it. Reload and review the current value."
        }
    }
}
public enum YouState: Sendable, Equatable {
    case idle, loading, content(YouSnapshot, issue: YouIssue?), failure(YouIssue)
    public var snapshot: YouSnapshot? { if case let .content(value, _) = self { value } else { nil } }
    public var issue: YouIssue? { switch self { case let .content(_, issue): issue; case let .failure(issue): issue; default: nil } }
}

@MainActor @Observable public final class YouModel {
    public private(set) var state: YouState = .idle
    public private(set) var profileDraft: ProfileDraft?
    @ObservationIgnored private let client: YouClient

    public init(client: YouClient) { self.client = client }

    public func load() async {
        let retained = state.snapshot
        state = .loading
        do { state = .content(try await client.load(), issue: nil) }
        catch { state = retained.map { .content($0, issue: Self.issue(error)) } ?? .failure(Self.issue(error)) }
    }

    public func retry() async { await load() }

    public func beginProfileEdit() {
        let profile = state.snapshot?.profile
        profileDraft = .init(displayName: profile?.displayName ?? "", headline: profile?.headline ?? "", biography: profile?.biography ?? "")
    }

    public func updateProfile(displayName: String, headline: String, biography: String) {
        guard profileDraft != nil else { return }
        profileDraft = .init(displayName: displayName, headline: headline, biography: biography)
    }

    public func cancelProfileEdit() { profileDraft = nil }

    public func saveProfile() async {
        guard let draft = profileDraft else { return }
        do { state = .content(try await client.saveProfile(draft), issue: nil); profileDraft = nil }
        catch { state = state.snapshot.map { .content($0, issue: Self.issue(error)) } ?? .failure(Self.issue(error)) }
    }

    private static func issue(_ error: any Error) -> YouIssue {
        if let contract = error as? YouContractError {
            switch contract {
            case .invalidProfile: return .invalidInput
            case .persistenceFailed: return .storageUnavailable
            }
        }
        if let storage = error as? StorageError {
            switch storage {
            case .missingKeyForExistingStore, .authenticationFailed, .integrityFailed, .schemaMismatch, .unsupportedMigration, .unsupportedSchemaVersion: return .recoveryRequired
            default: return .storageUnavailable
            }
        }
        return .storageUnavailable
    }
}

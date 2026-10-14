import Observation
import TaisaStorage

public enum YouIssue: Sendable, Equatable { case storageUnavailable, recoveryRequired, invalidInput, conflict }
public enum YouState: Sendable, Equatable {
    case idle, loading, content(YouSnapshot, issue: YouIssue?), failure(YouIssue)
    public var snapshot: YouSnapshot? { if case let .content(value, _) = self { value } else { nil } }
    public var issue: YouIssue? { switch self { case let .content(_, issue): issue; case let .failure(issue): issue; default: nil } }
}

@MainActor @Observable public final class YouModel {
    public private(set) var state: YouState = .idle
    public private(set) var profileDraft: ProfileDraft?
    public private(set) var pendingCapabilityReview: CapabilityChangeReview?
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

    public func setCapability(_ id: CapabilityID, to state: CapabilityGovernanceState) async {
        do { self.state = .content(try await client.setCapability(id, state), issue: nil) }
        catch { self.state = self.state.snapshot.map { .content($0, issue: Self.issue(error)) } ?? .failure(Self.issue(error)) }
    }

    public func requestCapabilityChange(_ id: CapabilityID, to requested: CapabilityGovernanceState) async {
        guard let current = state.snapshot?.capabilities.first(where: { $0.id == id })?.chosenState,
              current != requested else { return }
        if Self.rank(requested) > Self.rank(current) {
            pendingCapabilityReview = .init(id: id, from: current, to: requested)
        } else {
            pendingCapabilityReview = nil
            await setCapability(id, to: requested)
        }
    }

    public func confirmCapabilityChange() async {
        guard let review = pendingCapabilityReview else { return }
        pendingCapabilityReview = nil
        await setCapability(review.id, to: review.to)
    }

    public func cancelCapabilityChange() { pendingCapabilityReview = nil }

    private static func rank(_ state: CapabilityGovernanceState) -> Int {
        switch state {
        case .learning: 0
        case .ready: 1
        case .trial: 2
        case .trusted: 3
        }
    }

    private static func issue(_ error: any Error) -> YouIssue {
        if let contract = error as? YouContractError {
            switch contract {
            case .invalidProfile, .promotionEvidenceRequired: return .invalidInput
            case .staleDecision, .decisionCollision: return .conflict
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

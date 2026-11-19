import Foundation
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

public enum ProfileSaveState: Sendable, Equatable {
    case idle, waiting, saving, saved, invalid, failed
}

@MainActor @Observable public final class YouModel {
    public private(set) var state: YouState = .idle
    public private(set) var profileDraft: ProfileDraft?
    public private(set) var profileSaveState: ProfileSaveState = .idle
    public var profileValidation: ProfileInputValidation {
        guard let draft = profileDraft else {
            return ProfileInputValidator.validate(displayName: "", biography: "")
        }
        return ProfileInputValidator.validate(
            displayName: draft.displayName,
            biography: draft.biography
        )
    }
    @ObservationIgnored private let client: YouClient
    @ObservationIgnored private var savedDraft: ProfileDraft?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Bool, Never>?
    @ObservationIgnored private var editSession = UUID()

    public init(client: YouClient) { self.client = client }

    public func load() async {
        let retained = state.snapshot
        state = .loading
        do { state = .content(try await client.load(), issue: nil) }
        catch { state = retained.map { .content($0, issue: Self.issue(error)) } ?? .failure(Self.issue(error)) }
    }

    public func retry() async { await load() }

    public func beginProfileEdit() {
        guard profileDraft == nil else { return }
        editSession = UUID()
        profileSaveState = .idle
        let profile = state.snapshot?.profile
        profileDraft = .init(displayName: profile?.displayName ?? "", biography: profile?.biography ?? "")
        savedDraft = profileDraft
    }

    public func updateProfile(displayName: String, biography: String) {
        guard profileDraft != nil else { return }
        profileDraft = .init(displayName: displayName, biography: biography)
    }

    public func updateProfileBio(displayName: String, biography: String) {
        guard profileDraft != nil else { return }
        updateProfile(displayName: displayName, biography: biography)
        debounceTask?.cancel()
        guard profileValidation.isValid else {
            profileSaveState = .invalid
            return
        }
        profileSaveState = .waiting
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) }
            catch { return }
            guard let self else { return }
            self.debounceTask = nil
            _ = await self.flushProfileChanges()
        }
    }

    public func cancelProfileEdit() {
        debounceTask?.cancel()
        debounceTask = nil
        editSession = UUID()
        profileDraft = nil
        savedDraft = nil
        profileSaveState = .idle
    }

    /// Serializes writes and drains newer edits before reporting success.
    /// A completed older write never replaces the current editing draft.
    @discardableResult public func flushProfileChanges() async -> Bool {
        debounceTask?.cancel()
        debounceTask = nil
        guard profileValidation.isValid else {
            profileSaveState = .invalid
            return false
        }
        if let saveTask {
            guard await saveTask.value else { return false }
            // Another edit may arrive between the writer finishing and this waiter resuming.
            if profileDraft != savedDraft { return await flushProfileChanges() }
            return true
        }
        let session = editSession
        let task = Task { [weak self] () -> Bool in
            guard let self else { return false }
            defer { self.saveTask = nil }
            while self.editSession == session, let draft = self.profileDraft {
                if draft == self.savedDraft {
                    self.profileSaveState = .saved
                    return true
                }
                self.profileSaveState = .saving
                do {
                    let snapshot = try await self.client.saveProfile(draft)
                    guard self.editSession == session else { return false }
                    self.state = .content(snapshot, issue: nil)
                    self.savedDraft = draft
                } catch {
                    guard self.editSession == session else { return false }
                    self.state = self.state.snapshot.map { .content($0, issue: Self.issue(error)) }
                        ?? .failure(Self.issue(error))
                    self.profileSaveState = .failed
                    return false
                }
            }
            return self.editSession == session
        }
        saveTask = task
        return await task.value
    }

    @discardableResult public func finishProfileEditing() async -> Bool {
        guard profileValidation.isValid else {
            profileSaveState = .invalid
            return false
        }
        guard await flushProfileChanges() else { return false }
        while profileDraft != savedDraft {
            guard await flushProfileChanges() else { return false }
        }
        profileDraft = nil
        savedDraft = nil
        return true
    }

    public func saveProfile() async {
        _ = await finishProfileEditing()
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

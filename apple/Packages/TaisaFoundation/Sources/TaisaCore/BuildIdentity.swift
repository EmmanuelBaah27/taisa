public struct BuildIdentity: Equatable, Sendable {
    public let gitCommit: String
    public let gitBranch: String?
    public let isDirty: Bool
    public let buildNumber: String
    public let bundleIdentifier: String
    public let environment: TaisaEnvironment
    public let contractRevision: String

    public init(
        gitCommit: String,
        gitBranch: String?,
        isDirty: Bool,
        buildNumber: String,
        bundleIdentifier: String,
        environment: TaisaEnvironment,
        contractRevision: String
    ) {
        self.gitCommit = gitCommit
        self.gitBranch = gitBranch
        self.isDirty = isDirty
        self.buildNumber = buildNumber
        self.bundleIdentifier = bundleIdentifier
        self.environment = environment
        self.contractRevision = contractRevision
    }

    public var sourceDescription: String {
        let location = gitBranch ?? "detached"
        let state = isDirty ? "dirty" : "clean"
        return "\(gitCommit) (\(location), \(state))"
    }
}

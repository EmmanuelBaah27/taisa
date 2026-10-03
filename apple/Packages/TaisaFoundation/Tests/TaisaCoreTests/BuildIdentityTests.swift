import Testing
@testable import TaisaCore

@Test func detachedDirtyBuildRemainsExplicit() {
    let identity = BuildIdentity(
        gitCommit: "abc123",
        gitBranch: nil,
        isDirty: true,
        buildNumber: "7",
        bundleIdentifier: "com.taisa.app.dev",
        environment: .development,
        contractRevision: "fixtures-v1"
    )

    #expect(identity.sourceDescription == "abc123 (detached, dirty)")
}

@Test func cleanBranchBuildNamesItsBranch() {
    let identity = BuildIdentity(
        gitCommit: "def456",
        gitBranch: "feature/native",
        isDirty: false,
        buildNumber: "8",
        bundleIdentifier: "com.taisa.app.dev",
        environment: .development,
        contractRevision: "fixtures-v1"
    )

    #expect(identity.sourceDescription == "def456 (feature/native, clean)")
}

// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TaisaFoundation",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "TaisaCore", targets: ["TaisaCore"]),
        .library(name: "TaisaContracts", targets: ["TaisaContracts"]),
        .library(name: "TaisaDesignSystem", targets: ["TaisaDesignSystem"]),
        .library(name: "TaisaPreviewSupport", targets: ["TaisaPreviewSupport"]),
        .library(name: "TaisaStorage", targets: ["TaisaStorage"]),
        .library(name: "TaisaSecurity", targets: ["TaisaSecurity"]),
        .library(name: "TaisaSync", targets: ["TaisaSync"]),
        .library(name: "TaisaCloudKit", targets: ["TaisaCloudKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sqlcipher/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(name: "TaisaCore"),
        .target(name: "TaisaContracts"),
        .target(name: "TaisaDesignSystem"),
        .target(name: "TaisaPreviewSupport", dependencies: ["TaisaCore"]),
        .target(name: "TaisaStorage", dependencies: [
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),
        .target(name: "TaisaSecurity"),
        .target(name: "TaisaSync", dependencies: [
            "TaisaStorage",
            "TaisaSecurity",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),
        .target(name: "TaisaCloudKit", dependencies: ["TaisaSync", "TaisaStorage", "TaisaSecurity"]),
        .testTarget(name: "TaisaCoreTests", dependencies: ["TaisaCore"]),
        .testTarget(name: "TaisaContractsTests", dependencies: ["TaisaContracts"]),
        .testTarget(name: "TaisaDesignSystemTests", dependencies: ["TaisaDesignSystem"]),
        .testTarget(name: "TaisaPreviewSupportTests", dependencies: ["TaisaPreviewSupport"]),
        .testTarget(name: "TaisaStorageTests", dependencies: [
            "TaisaStorage",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),
        .testTarget(name: "TaisaSecurityTests", dependencies: ["TaisaSecurity"]),
        .testTarget(name: "TaisaSyncTests", dependencies: ["TaisaSync", "TaisaStorage", "TaisaSecurity"]),
        .testTarget(name: "TaisaCloudKitTests", dependencies: ["TaisaCloudKit", "TaisaSync", "TaisaSecurity", "TaisaStorage", .product(name: "GRDB", package: "GRDB.swift")]),
    ]
)

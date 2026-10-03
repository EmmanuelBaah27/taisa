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
    ],
    targets: [
        .target(name: "TaisaCore"),
        .target(name: "TaisaContracts"),
        .target(name: "TaisaDesignSystem"),
        .target(name: "TaisaPreviewSupport", dependencies: ["TaisaCore"]),
        .testTarget(name: "TaisaCoreTests", dependencies: ["TaisaCore"]),
        .testTarget(name: "TaisaDesignSystemTests", dependencies: ["TaisaDesignSystem"]),
    ]
)

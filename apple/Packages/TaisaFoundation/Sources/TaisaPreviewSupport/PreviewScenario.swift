import SwiftUI

public enum PreviewDeviceFamily: String, CaseIterable, Sendable {
    case phone
    case tablet
    case adaptive

    public var title: String {
        switch self {
        case .phone: "iPhone"
        case .tablet: "iPad"
        case .adaptive: "iPhone and iPad"
        }
    }
}

public enum PreviewContentSize: String, Sendable {
    case standard
    case accessibilityExtraExtraExtraLarge
}

public struct PreviewAccessibilitySettings: Equatable, Sendable {
    public let contentSize: PreviewContentSize
    public let reducedMotion: Bool
    public let increasedContrast: Bool

    public init(
        contentSize: PreviewContentSize = .standard,
        reducedMotion: Bool = false,
        increasedContrast: Bool = false
    ) {
        self.contentSize = contentSize
        self.reducedMotion = reducedMotion
        self.increasedContrast = increasedContrast
    }

    public static let `default` = PreviewAccessibilitySettings()

    public var summary: String {
        var requirements = [contentSize == .standard ? "Standard text" : "Accessibility XXXL text"]
        if reducedMotion { requirements.append("Reduce Motion") }
        if increasedContrast { requirements.append("Increase Contrast") }
        return requirements.joined(separator: " · ")
    }
}

public enum PreviewReadiness: String, Sendable {
    case ready
    case planned
}

public struct PreviewScenario: Identifiable, @unchecked Sendable {
    public let identifier: String
    public let title: String
    public let deviceFamily: PreviewDeviceFamily
    public let accessibility: PreviewAccessibilitySettings
    public let readiness: PreviewReadiness
    private let rootViewFactory: @MainActor @Sendable () -> AnyView

    public var id: String { identifier }

    public init(
        identifier: String,
        title: String,
        deviceFamily: PreviewDeviceFamily,
        accessibility: PreviewAccessibilitySettings,
        readiness: PreviewReadiness,
        rootViewFactory: @escaping @MainActor @Sendable () -> AnyView
    ) {
        self.identifier = identifier
        self.title = title
        self.deviceFamily = deviceFamily
        self.accessibility = accessibility
        self.readiness = readiness
        self.rootViewFactory = rootViewFactory
    }

    @MainActor
    public func makeRootView() -> AnyView {
        rootViewFactory()
    }
}

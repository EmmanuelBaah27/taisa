import SwiftUI
import TaisaPreviewSupport

@MainActor
enum YouScenarios {
    static let scenarios: [PreviewScenario] = [
        scenario("you.content", "You content", .phone, mode: .content),
        scenario("you.permissionDenied", "You permission denied", .phone, mode: .permissionDenied),
        scenario("you.gatewayUnavailable", "You gateway unavailable", .phone, mode: .gatewayUnavailable),
        scenario("you.recoveryRequired", "You recovery required", .phone, mode: .recoveryRequired),
        scenario("you.failure", "You failure", .phone, mode: .failure),
        scenario(
            "you.accessibilityText",
            "You accessibility text",
            .phone,
            accessibility: .init(contentSize: .accessibilityExtraExtraExtraLarge),
            mode: .content
        ),
    ]

    private static func scenario(
        _ identifier: String,
        _ title: String,
        _ family: PreviewDeviceFamily,
        accessibility: PreviewAccessibilitySettings = .default,
        mode: YouScenarioMode
    ) -> PreviewScenario {
        .init(identifier: identifier, title: title, deviceFamily: family, accessibility: accessibility, readiness: .ready) {
            AnyView(YouScenarioView(mode: mode))
        }
    }
}

enum YouScenarioMode: Sendable, Equatable {
    case content
    case permissionDenied
    case gatewayUnavailable
    case recoveryRequired
    case failure
}

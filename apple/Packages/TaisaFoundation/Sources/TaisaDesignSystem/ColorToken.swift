import SwiftUI

public enum TaisaColor: String, CaseIterable, Sendable {
    case background = "#FFFFFF"
    case foreground = "#060707"
    case mutedForeground = "#5F646A"
    case primaryAction = "#CDEC1A"
    case border = "#E6E6E6"
    case raisedSurface = "#F9F9F9"
    case selectedSurface = "#F3F3F3"
    case destructive = "#C60000"
    case warning = "#E46300"

    public var hex: String { rawValue }

    public var color: Color {
        Color(taisaHex: rawValue)
    }
}

private extension Color {
    init(taisaHex hex: String) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

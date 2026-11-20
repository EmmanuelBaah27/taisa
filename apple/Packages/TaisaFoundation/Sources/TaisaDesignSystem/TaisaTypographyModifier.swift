import SwiftUI

public extension View {
    func taisaTypography(_ role: TaisaTypography) -> some View {
        self.font(role.font)
            .lineSpacing(role.lineSpacing)
            .tracking(role.tracking)
    }
}

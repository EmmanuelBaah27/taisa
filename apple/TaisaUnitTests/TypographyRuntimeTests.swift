import TaisaDesignSystem
import UIKit
import XCTest

final class TypographyRuntimeTests: XCTestCase {
    func testBundledSemanticFontsResolveWithoutSystemFallback() {
        let roles: [TaisaTypography] = [.body, .display]

        for role in roles {
            XCTAssertNotNil(
                UIFont(name: role.fontName, size: role.pointSize),
                "Missing registered font \(role.fontName) for \(role.rawValue)"
            )
        }
    }
}

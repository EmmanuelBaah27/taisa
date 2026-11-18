import CoreText
import Foundation

/// Scoped to the approved profile typography; does not retheme other screens.
enum TaisaProfileFonts {
    private static let registration: Void = {
        for name in ["ScoutieSans", "Inter"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
    static func register() { _ = registration }
}

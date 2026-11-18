import CoreText
import Foundation

/// Registers the bundled families used by every semantic typography role.
enum TaisaProfileFonts {
    private static let registration: Void = {
        for name in ["ScoutieSans", "Inter"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
    static func register() { _ = registration }
}

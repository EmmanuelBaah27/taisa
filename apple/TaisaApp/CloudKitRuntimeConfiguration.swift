import Foundation

enum CloudKitRuntimeConfiguration {
    static func containerIdentifier(for bundleIdentifier: String?) -> String? {
        switch bundleIdentifier {
        case "com.taisa.app.dev": "iCloud.com.taisa.app.dev"
        case "com.taisa.app": "iCloud.com.taisa.app"
        default: nil
        }
    }
}

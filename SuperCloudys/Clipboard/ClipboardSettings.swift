import Foundation

final class ClipboardSettings {

    static let shared = ClipboardSettings()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let excludedApps = "clipboard_excludedApps"
        static let retentionDays = "clipboard_retentionDays"
        static let isPaused = "clipboard_isPaused"
        static let maxEntries = "clipboard_maxEntries"
    }

    private static let defaultExcludedApps: Set<String> = [
        "com.apple.keychainaccess",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
        "com.apple.Passwords"
    ]

    var excludedApps: Set<String> {
        get {
            if let arr = defaults.array(forKey: Keys.excludedApps) as? [String] {
                return Set(arr)
            }
            return Self.defaultExcludedApps
        }
        set { defaults.set(Array(newValue), forKey: Keys.excludedApps) }
    }

    var retentionDays: Int {
        get { max(defaults.integer(forKey: Keys.retentionDays), 0) }
        set { defaults.set(newValue, forKey: Keys.retentionDays) }
    }

    var isPaused: Bool {
        get { defaults.bool(forKey: Keys.isPaused) }
        set { defaults.set(newValue, forKey: Keys.isPaused) }
    }

    var maxEntries: Int {
        get {
            let val = defaults.integer(forKey: Keys.maxEntries)
            return val > 0 ? val : 500
        }
        set { defaults.set(newValue, forKey: Keys.maxEntries) }
    }

    func isAppExcluded(_ bundleID: String) -> Bool {
        excludedApps.contains(bundleID)
    }
}

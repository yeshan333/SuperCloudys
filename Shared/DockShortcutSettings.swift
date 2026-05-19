import Foundation

enum DockShortcutSettings {
    private static let enabledKey = "DockShortcutsEnabled"

    static var shortcutsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
}

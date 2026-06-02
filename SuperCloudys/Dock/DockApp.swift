import Foundation

struct DockApp: Identifiable, Equatable {
    var id: String { bundleID }
    let name: String
    let bundleID: String
    let appPath: String
    let shortcutLabel: String?

    static let maxShortcutApps = 10

    static func shortcutLabel(forIndex index: Int) -> String? {
        switch index {
        case 0...8: return String(index + 1)
        case 9: return "0"
        default: return nil
        }
    }
}

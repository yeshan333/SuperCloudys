import Foundation

/// 输入法的不同模式可能共享输入源 ID，需要一起保存模式 ID。
struct InputSourceIdentifier: Codable, Hashable, Sendable {
    let sourceID: String
    let modeID: String?

    var styleKey: String { sourceID + (modeID.map { "::" + $0 } ?? "") }
}

struct InputSourceIndicatorStyle: Codable, Equatable, Sendable {
    let backgroundHex: String
    let foregroundHex: String

    static let standard = InputSourceIndicatorStyle(backgroundHex: "000000d1", foregroundHex: "ffffffff")
}

struct AppInputSourceRule: Codable, Identifiable, Equatable, Sendable {
    var id: String { bundleID }
    let bundleID: String
    let appName: String
    let appPath: String
    let inputSource: InputSourceIdentifier
    let inputSourceName: String
}

final class InputSourceSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: "SuperCloudys.inputSource.enabled") }
        set { defaults.set(newValue, forKey: "SuperCloudys.inputSource.enabled") }
    }

    var showsIndicator: Bool {
        get { defaults.object(forKey: "SuperCloudys.inputSource.showsIndicator") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "SuperCloudys.inputSource.showsIndicator") }
    }

    var indicatorStyles: [String: InputSourceIndicatorStyle] {
        get {
            guard let data = defaults.data(forKey: "SuperCloudys.inputSource.indicatorStyles"),
                  let styles = try? JSONDecoder().decode([String: InputSourceIndicatorStyle].self, from: data)
            else { return [:] }
            return styles
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: "SuperCloudys.inputSource.indicatorStyles")
        }
    }

    func indicatorStyle(for id: InputSourceIdentifier) -> InputSourceIndicatorStyle {
        let styles = indicatorStyles
        return styles[id.styleKey] ?? styles[id.sourceID] ?? .standard
    }

    var rules: [AppInputSourceRule] {
        get {
            guard let data = defaults.data(forKey: "SuperCloudys.inputSource.rules"),
                  let rules = try? JSONDecoder().decode([AppInputSourceRule].self, from: data)
            else { return [] }
            return rules
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: "SuperCloudys.inputSource.rules")
        }
    }
}

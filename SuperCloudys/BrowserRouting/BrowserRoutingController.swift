import AppKit
import Combine

struct InstalledBrowser: Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL
}

@MainActor
protocol BrowserWorkspace {
    func installedBrowsers() -> [InstalledBrowser]
    func defaultBrowserID(for scheme: String) -> String?
    func setDefaultBrowser(for scheme: String) async throws
    func open(_ url: URL, in browser: InstalledBrowser) async throws
}

@MainActor
struct SystemBrowserWorkspace: BrowserWorkspace {
    func installedBrowsers() -> [InstalledBrowser] {
        var seen = Set<String>()
        return ["https", "http"].flatMap { scheme in
            NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "\(scheme)://example.com")!)
        }.compactMap { url in
            guard let id = Bundle(url: url)?.bundleIdentifier,
                  id != BrowserRoutingController.ownBundleID,
                  seen.insert(id).inserted else { return nil }
            return InstalledBrowser(
                id: id, name: FileManager.default.displayName(atPath: url.path), url: url
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func defaultBrowserID(for scheme: String) -> String? {
        guard let url = URL(string: "\(scheme)://example.com"),
              let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return nil }
        return Bundle(url: app)?.bundleIdentifier
    }

    func setDefaultBrowser(for scheme: String) async throws {
        try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
    }

    func open(_ url: URL, in browser: InstalledBrowser) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: browser.url, configuration: configuration)
    }
}

@MainActor
final class BrowserRoutingController: ObservableObject {
    static let shared = BrowserRoutingController()
    static let ownBundleID = "com.yeshan333.SuperCloudys"
    static let settingsKey = "SuperCloudys.browserRouting"

    @Published private(set) var configuration: BrowserRoutingConfiguration
    @Published private(set) var browsers: [InstalledBrowser] = []
    @Published private(set) var isDefaultBrowser = false
    @Published private(set) var isSettingDefault = false
    @Published private(set) var lastError: String?

    private let defaults: UserDefaults
    private let workspace: any BrowserWorkspace

    init(defaults: UserDefaults = .standard, workspace: (any BrowserWorkspace)? = nil) {
        self.defaults = defaults
        self.workspace = workspace ?? SystemBrowserWorkspace()
        if let data = defaults.data(forKey: Self.settingsKey) {
            do {
                configuration = try JSONDecoder().decode(BrowserRoutingConfiguration.self, from: data)
                // 修正旧配置中的自身目标，避免在选择器里重新出现“不可用”的自身选项。
                if configuration.fallbackBrowserBundleID == Self.ownBundleID {
                    configuration.fallbackBrowserBundleID = "com.google.Chrome"
                }
                for index in configuration.rules.indices where configuration.rules[index].browserBundleID == Self.ownBundleID {
                    configuration.rules[index].browserBundleID = configuration.fallbackBrowserBundleID
                }
            } catch {
                configuration = BrowserRoutingConfiguration()
                lastError = "无法读取浏览器规则，将使用兜底浏览器。原配置仍保留，修改设置后会覆盖。"
            }
        } else {
            configuration = BrowserRoutingConfiguration()
        }
        refreshBrowsers()
    }

    func refreshBrowsers() {
        browsers = workspace.installedBrowsers().filter { $0.id != Self.ownBundleID }
        isDefaultBrowser = ["http", "https"].allSatisfy { workspace.defaultBrowserID(for: $0) == Self.ownBundleID }
    }

    func setEnabled(_ enabled: Bool) {
        var next = configuration
        next.isEnabled = enabled
        save(next)
    }

    func setFallbackBrowser(_ id: String) {
        guard browsers.contains(where: { $0.id == id }), id != Self.ownBundleID else { return }
        var next = configuration
        next.fallbackBrowserBundleID = id
        save(next)
    }

    @discardableResult
    func saveRule(_ rule: BrowserRoutingRule) -> Bool {
        guard rule.validationError == nil, rule.browserBundleID != Self.ownBundleID else { return false }
        var next = configuration
        if let index = next.rules.firstIndex(where: { $0.id == rule.id }) {
            next.rules[index] = rule
        } else {
            next.rules.append(rule)
        }
        return save(next)
    }

    func removeRule(_ id: UUID) {
        var next = configuration
        next.rules.removeAll { $0.id == id }
        save(next)
    }

    func moveRule(_ id: UUID, offset: Int) {
        var next = configuration
        guard let index = next.rules.firstIndex(where: { $0.id == id }),
              next.rules.indices.contains(index + offset) else { return }
        next.rules.swapAt(index, index + offset)
        save(next)
    }

    func makeDefaultBrowser() async {
        guard !isSettingDefault else { return }
        // 接管链接前先保存兜底浏览器，重启后也能继续打开未命中的链接。
        guard save(configuration) else { return }
        isSettingDefault = true
        defer {
            isSettingDefault = false
            refreshBrowsers()
        }
        do {
            for scheme in ["http", "https"] {
                if workspace.defaultBrowserID(for: scheme) != Self.ownBundleID {
                    try await workspace.setDefaultBrowser(for: scheme)
                }
            }
        } catch {
            lastError = "启用系统链接分流失败：\(error.localizedDescription)。请重试。"
        }
    }

    func preview(_ url: URL) -> String {
        guard BrowserRoutingRule.isWebURL(url) else { return "请输入完整的 http:// 或 https:// URL。" }
        let rule = configuration.matchingRule(for: url)
        guard let id = destinationIDs(for: url).first,
              let browser = browsers.first(where: { $0.id == id }) else { return "没有可用浏览器。" }
        if let rule, rule.browserBundleID == id {
            return "命中\(rule.kind.title)规则「\(rule.pattern)」 → \(browser.name)"
        }
        return "\(rule == nil ? "未命中规则或分流已暂停" : "规则目标不可用") → \(browser.name)（兜底）"
    }

    func open(_ url: URL) async {
        guard BrowserRoutingConfiguration.supports(url) else { return }
        refreshBrowsers()
        let destinations = destinationIDs(for: url).compactMap { id in browsers.first { $0.id == id } }
        var failure: Error?
        for browser in destinations {
            do {
                try await workspace.open(url, in: browser)
                lastError = nil
                return
            } catch {
                failure = error
            }
        }
        lastError = failure.map { "打开链接失败：\($0.localizedDescription)" } ?? "没有可用浏览器，请安装浏览器后重试。"
    }

    private func destinationIDs(for url: URL) -> [String] {
        configuration.destinations(for: url, availableBrowserIDs: browsers.map(\.id), ownBundleID: Self.ownBundleID)
    }

    @discardableResult
    private func save(_ next: BrowserRoutingConfiguration) -> Bool {
        do {
            defaults.set(try JSONEncoder().encode(next), forKey: Self.settingsKey)
            configuration = next
            lastError = nil
            return true
        } catch {
            lastError = "保存浏览器规则失败：\(error.localizedDescription)"
            return false
        }
    }
}

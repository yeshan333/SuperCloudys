import Foundation

enum BrowserRuleKind: String, Codable, CaseIterable, Identifiable {
    case domain, pathPrefix, regularExpression

    var id: String { rawValue }

    var title: String {
        switch self {
        case .domain: return "域名"
        case .pathPrefix: return "路径前缀"
        case .regularExpression: return "URL 正则表达式"
        }
    }
}

struct BrowserRoutingRule: Codable, Equatable, Identifiable {
    var id = UUID()
    var isEnabled = true
    var kind: BrowserRuleKind = .domain
    var pattern = ""
    // 路径规则可额外限定域名；空值表示任意域名。
    var domain = ""
    var includesSubdomains = true
    var browserBundleID = "com.google.Chrome"

    var validationError: String? {
        guard !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "请填写匹配内容。"
        }
        guard !browserBundleID.isEmpty else { return "请选择目标浏览器。" }
        switch kind {
        case .domain:
            if Self.normalizedDomain(pattern) == nil {
                return "请输入域名，例如 example.com，不含协议、端口或路径。"
            }
        case .pathPrefix:
            if !pattern.hasPrefix("/") || pattern.contains("?") || pattern.contains("#") {
                return "路径需以 / 开头，不含查询参数或片段。"
            }
            if !domain.isEmpty && Self.normalizedDomain(domain) == nil {
                return "限定域名格式不正确，例如 example.com。"
            }
        case .regularExpression:
            if (try? NSRegularExpression(pattern: pattern)) == nil {
                return "正则表达式无效，请检查括号和转义。"
            }
        }
        return nil
    }

    func matches(_ url: URL) -> Bool {
        guard isEnabled, validationError == nil, Self.isWebURL(url) else { return false }
        switch kind {
        case .domain:
            return matchesDomain(url.host, pattern: pattern)
        case .pathPrefix:
            guard domain.isEmpty || matchesDomain(url.host, pattern: domain) else { return false }
            // 使用编码后的路径，避免把 %2F 误认为路径分隔符；不匹配 query 和 fragment。
            let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
            return (path.isEmpty ? "/" : path).hasPrefix(pattern)
        case .regularExpression:
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            let value = url.absoluteString
            var matched = false
            let deadline = ProcessInfo.processInfo.systemUptime + 0.1
            // 限制复杂表达式的运行时间，防止阻塞菜单栏主线程。
            regex.enumerateMatches(
                in: value, options: [.reportProgress],
                range: NSRange(value.startIndex..., in: value)
            ) { result, _, stop in
                if ProcessInfo.processInfo.systemUptime > deadline {
                    stop.pointee = true
                } else if result != nil {
                    matched = true
                    stop.pointee = true
                }
            }
            return matched
        }
    }

    static func isWebURL(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && !(url.host ?? "").isEmpty
    }

    private func matchesDomain(_ host: String?, pattern: String) -> Bool {
        guard let host, let host = Self.normalizedDomain(host),
              let domain = Self.normalizedDomain(pattern) else { return false }
        return host == domain || (includesSubdomains && host.hasSuffix("." + domain))
    }

    private static func normalizedDomain(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty,
              !value.contains(where: { $0.isWhitespace }),
              !value.contains(where: { "/:?#@*\\".contains($0) }),
              let url = URL(string: "https://" + value), let host = url.host else { return nil }
        let normalized = host.lowercased().hasSuffix(".") ? String(host.lowercased().dropLast()) : host.lowercased()
        guard !normalized.isEmpty,
              normalized.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty }) else {
            return nil
        }
        return normalized
    }
}

struct BrowserRoutingConfiguration: Codable, Equatable {
    var isEnabled = true
    var fallbackBrowserBundleID = "com.google.Chrome"
    var rules: [BrowserRoutingRule] = [
        BrowserRoutingRule(
            pattern: "gitlab.lingxigames-inc.com", includesSubdomains: false,
            browserBundleID: "org.mozilla.firefoxdeveloperedition"
        )
    ]

    func matchingRule(for url: URL) -> BrowserRoutingRule? {
        isEnabled ? rules.first(where: { $0.matches(url) }) : nil
    }

    static func supports(_ url: URL) -> Bool {
        BrowserRoutingRule.isWebURL(url) || (
            url.isFileURL && !url.hasDirectoryPath
                && ["html", "htm", "xhtml"].contains(url.pathExtension.lowercased())
        )
    }

    // 明确指定应用打开，不再调用系统默认处理器，避免路由回自身。
    func destinations(for url: URL, availableBrowserIDs: [String], ownBundleID: String) -> [String] {
        // 系统默认浏览器设置可能同时接管 HTML 文件。文件不匹配网页规则，直接使用兜底。
        guard Self.supports(url) else { return [] }
        let candidates = [matchingRule(for: url)?.browserBundleID, fallbackBrowserBundleID, "com.apple.Safari"]
            .compactMap { $0 } + availableBrowserIDs
        var seen = Set<String>()
        return candidates.filter {
            $0 != ownBundleID && availableBrowserIDs.contains($0) && seen.insert($0).inserted
        }
    }
}

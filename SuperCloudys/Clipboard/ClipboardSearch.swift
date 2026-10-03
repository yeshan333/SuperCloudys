import Foundation

/// 保留全文、大小写不敏感及 Unicode 等价匹配，不复制一份归一化正文。
enum ClipboardSearch {
    static func matches(_ entry: ClipboardEntry, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return contains(entry.title, query: query)
            || (entry.plainText.map { contains($0, query: query) } ?? false)
            || (entry.sourceAppName.map { contains($0, query: query) } ?? false)
    }

    static func filter(
        _ entries: [ClipboardEntry],
        query: String,
        type: ClipboardContentType? = nil,
        isCancelled: () -> Bool = { false }
    ) -> [ClipboardEntry]? {
        var result: [ClipboardEntry] = []
        for entry in entries {
            // Swift 任务取消是协作式的，避免过期查询继续扫描整个历史。
            guard !isCancelled() else { return nil }
            if let type {
                let matchesType = type == .text
                    ? entry.contentType == .text || entry.contentType == .richText
                    : entry.contentType == type
                if !matchesType { continue }
            }
            // 及时释放 String 桥接产生的临时对象，避免扫描大历史时堆积。
            if autoreleasepool(invoking: { matches(entry, query: query) }) {
                result.append(entry)
            }
        }
        return isCancelled() ? nil : result
    }

    static func sorted(_ entries: [ClipboardEntry]) -> [ClipboardEntry] {
        entries.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return (lhs.lastUsedAt ?? lhs.createdAt) > (rhs.lastUsedAt ?? rhs.createdAt)
        }
    }

    private static func contains(_ text: String, query: String) -> Bool {
        // fastestEncoding 复用字符串的编码信息，避免为了判断 ASCII 再扫描全文。
        // Unicode 的原生匹配规则与 Swift 存在差异，保留原 String 搜索语义。
        guard text.fastestEncoding == .ascii, query.fastestEncoding == .ascii else {
            return text.range(of: query, options: .caseInsensitive) != nil
        }
        // 使用 Foundation 的原生搜索，避免 Swift String 在大段正文上逐字符转换。
        let candidate = (text as NSString).range(of: query, options: .caseInsensitive)
        guard candidate.location != NSNotFound else { return false }
        if let range = Range(candidate, in: text),
           range.lowerBound.samePosition(in: text) != nil,
           range.upperBound.samePosition(in: text) != nil {
            return true
        }
        // ASCII 中 CRLF 也是一个字符。回退后仍能寻找后面的独立 CR 或 LF。
        return text.range(of: query, options: .caseInsensitive) != nil
    }
}

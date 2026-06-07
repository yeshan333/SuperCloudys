import Foundation

enum ClipboardContentType: String, Codable, CaseIterable {
    case text
    case richText
    case url
    case fileGroup
    case image
    case color
    case unknown
}

struct ClipboardEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let contentType: ClipboardContentType
    let plainText: String?
    let title: String
    let subtitle: String?
    let createdAt: Date
    let sourceAppBundleID: String?
    let sourceAppName: String?
    var isPinned: Bool
    var lastUsedAt: Date?
    let fingerprint: String
    let imagePath: String?
    let thumbnailPath: String?
    let filePaths: [String]?
    let colorHex: String?

    var characterCount: Int? {
        plainText?.count
    }

    var wordCount: Int? {
        guard let text = plainText, !text.isEmpty else { return nil }
        var count = 0
        text.enumerateSubstrings(
            in: text.startIndex...,
            options: [.byWords, .substringNotRequired]
        ) { _, _, _, _ in count += 1 }
        return count
    }

    static func fingerprint(type: ClipboardContentType, content: String?) -> String {
        let raw = "\(type.rawValue):\(content ?? "")"
        var hash: UInt64 = 5381
        for byte in raw.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }
}

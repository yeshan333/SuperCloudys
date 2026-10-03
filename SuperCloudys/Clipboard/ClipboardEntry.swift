import Foundation
import CryptoKit

enum ClipboardContentType: String, Codable, CaseIterable, Sendable {
    case text
    case richText
    case url
    case fileGroup
    case image
    case color
    case unknown
}

struct ClipboardEntry: Identifiable, Codable, Hashable, Sendable {
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
        var hash: UInt64 = 5381
        update(&hash, with: type.rawValue.utf8)
        hash = hash &* 33 &+ 58 // ":"
        update(&hash, with: (content ?? "").utf8)
        return String(hash, radix: 16)
    }

    static func fingerprint(type: ClipboardContentType, data: Data) -> String {
        var hash = SHA256()
        hash.update(data: Data((type.rawValue + ":").utf8))
        hash.update(data: data)
        return "sha256:" + hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func hasSameContent(as other: ClipboardEntry) -> Bool {
        guard contentType == other.contentType else { return false }
        if contentType == .image {
            // Old image fingerprints are weak hashes; never discard an image on that basis.
            return fingerprint.hasPrefix("sha256:") && fingerprint == other.fingerprint
        }
        guard let plainText, let otherText = other.plainText else { return false }
        return plainText.utf8.elementsEqual(otherText.utf8)
            && filePaths == other.filePaths && colorHex == other.colorHex
    }

    private static func update<S: Sequence>(
        _ hash: inout UInt64,
        with bytes: S
    ) where S.Element == UInt8 {
        for byte in bytes {
            hash = hash &* 33 &+ UInt64(byte)
        }
    }
}

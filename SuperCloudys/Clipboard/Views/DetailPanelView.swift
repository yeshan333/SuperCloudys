import SwiftUI
import AppKit

struct DetailPanelView: View {
    let entry: ClipboardEntry?

    var body: some View {
        VStack(spacing: 0) {
            contentPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if entry != nil {
                Divider()

                informationPanel
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        if let entry {
            ScrollView {
                previewContent(for: entry)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .id(entry.id)
        } else {
            Text("未选择")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func previewContent(for entry: ClipboardEntry) -> some View {
        switch entry.contentType {
        case .color:
            if let hex = entry.colorHex {
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: hex) ?? .gray)
                        .frame(height: 60)
                    Text(hex).font(.system(.body, design: .monospaced))
                }
            }
        case .image:
            if let path = entry.thumbnailPath ?? entry.imagePath {
                AsyncImageView(path: path)
                    .frame(maxHeight: 200)
                    .cornerRadius(6)
            } else {
                Text(entry.title)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        default:
            let text = entry.plainText ?? entry.title
            let limit = 400
            let prefix = String(text.prefix(limit + 1))
            let previewText = prefix.count > limit
                ? String(prefix.prefix(limit)) + "\n\n...（预览已截断）"
                : prefix
            Text(previewText)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.primary.opacity(0.8))
        }
    }

    @ViewBuilder
    private var informationPanel: some View {
        if let entry {
            VStack(alignment: .leading, spacing: 4) {
                Text(primaryMetadata(for: entry))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let stats = statsMetadata(for: entry) {
                    Text(stats)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func primaryMetadata(for entry: ClipboardEntry) -> String {
        [
            entry.sourceAppName ?? "未知来源",
            entry.contentType.displayName,
            formatDate(entry.createdAt)
        ].joined(separator: " · ")
    }

    private func statsMetadata(for entry: ClipboardEntry) -> String? {
        if let text = entry.plainText {
            let byteCount = text.utf8.count
            if byteCount > 64 * 1024 {
                return Self.byteCountFormatter.string(fromByteCount: Int64(byteCount))
            }
        }
        var parts: [String] = []
        if let count = entry.characterCount {
            parts.append("\(count) 字符")
        }
        if let words = entry.wordCount {
            parts.append("\(words) 词")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = Self.timeFormatter.string(from: date)

        if calendar.isDateInToday(date) { return "今天 \(time)" }
        if calendar.isDateInYesterday(date) { return "昨天 \(time)" }
        return Self.dateFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter
    }()
}

// MARK: - Async Image with Cache

private struct AsyncImageView: View {
    let path: String
    @State private var nsImage: NSImage?
    @State private var loadingPath: String?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if loadFailed {
                ContentUnavailableView("图片不可用", systemImage: "photo.badge.exclamationmark")
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { loadImage() }
        .onChange(of: path) {
            nsImage = nil
            loadFailed = false
            loadImage()
        }
    }

    private func loadImage() {
        let currentPath = path
        loadingPath = currentPath
        loadFailed = false
        if let cached = ImageCache.shared.get(currentPath) {
            nsImage = cached
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let loaded = NSImage(contentsOfFile: currentPath) else {
                DispatchQueue.main.async {
                    guard loadingPath == currentPath else { return }
                    loadFailed = true
                }
                return
            }
            ImageCache.shared.set(loaded, forKey: currentPath)
            DispatchQueue.main.async {
                guard loadingPath == currentPath else { return }
                nsImage = loaded
            }
        }
    }
}

private final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, NSImage>()

    init() { cache.countLimit = 30 }

    func get(_ key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func set(_ image: NSImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}

extension Color {
    init?(hex: String) {
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("#") { str.removeFirst() }
        guard [6, 8].contains(str.count), let val = UInt64(str, radix: 16) else { return nil }
        let rgb = str.count == 8 ? val >> 8 : val
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        let a = str.count == 8 ? Double(val & 0xFF) / 255.0 : 1
        self.init(red: r, green: g, blue: b, opacity: a)
    }
}

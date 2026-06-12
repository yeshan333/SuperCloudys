import SwiftUI
import AppKit

struct DetailPanelView: View {
    let entry: ClipboardEntry?
    let onPaste: () -> Void
    let onCopy: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            contentPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            informationPanel
                .frame(maxWidth: .infinity)
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
            Text("No selection")
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
            let previewText = text.count > limit ? String(text.prefix(limit)) + "\n\n... (\(text.count) chars, truncated for preview)" : text
            Text(previewText)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.primary.opacity(0.8))
        }
    }

    @ViewBuilder
    private var informationPanel: some View {
        if let entry {
            VStack(alignment: .leading, spacing: 8) {
                Text("Information")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    InfoRow(label: "Source", value: entry.sourceAppName ?? "Unknown")
                    Divider().padding(.leading, 12)
                    InfoRow(label: "Content type", value: entry.contentType.displayName)
                    
                    if let count = entry.characterCount {
                        Divider().padding(.leading, 12)
                        InfoRow(label: "Characters", value: "\(count)")
                    }
                    if let words = entry.wordCount {
                        Divider().padding(.leading, 12)
                        InfoRow(label: "Words", value: "\(words)")
                    }
                    Divider().padding(.leading, 12)
                    InfoRow(label: "Copied at", value: formatDate(entry.createdAt))
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let time = formatter.string(from: date)

        if calendar.isDateInToday(date) { return "Today at \(time)" }
        if calendar.isDateInYesterday(date) { return "Yesterday at \(time)" }
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// MARK: - Async Image with Cache

private struct AsyncImageView: View {
    let path: String
    @State private var nsImage: NSImage?
    @State private var loadingPath: String?

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { loadImage() }
        .onChange(of: path) { _ in
            nsImage = nil
            loadImage()
        }
    }

    private func loadImage() {
        let currentPath = path
        loadingPath = currentPath
        if let cached = ImageCache.shared.get(currentPath) {
            nsImage = cached
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let loaded = NSImage(contentsOfFile: currentPath) else { return }
            ImageCache.shared.set(loaded, forKey: currentPath)
            DispatchQueue.main.async {
                guard loadingPath == currentPath else { return }
                nsImage = loaded
            }
        }
    }
}

private final class ImageCache {
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
        guard str.count == 6, let val = UInt64(str, radix: 16) else { return nil }
        let r = Double((val >> 16) & 0xFF) / 255.0
        let g = Double((val >> 8) & 0xFF) / 255.0
        let b = Double(val & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

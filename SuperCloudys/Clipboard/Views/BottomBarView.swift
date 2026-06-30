import SwiftUI

struct BottomBarView: View {
    let appName: String?
    let onPaste: () -> Void
    let onCopy: () -> Void
    let onClearUnpinned: () -> Void
    let onClearAll: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Spacer()

            Button(action: onCopy) {
                Label("复制", systemImage: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onPaste) {
                HStack(spacing: 6) {
                    Text(pasteLabel)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundColor(.white)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 1, height: 16)

            Menu {
                Button("清理未固定历史") {
                    onClearUnpinned()
                }
                Button("清空所有历史", role: .destructive) {
                    onClearAll()
                }
            } label: {
                HStack(spacing: 4) {
                    Text("更多")
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.22))
    }

    private var pasteLabel: String {
        if let name = appName {
            return "粘贴到 \(name)"
        }
        return "粘贴"
    }
}

import SwiftUI

struct BottomBarView: View {
    let appName: String?
    let onPaste: () -> Void
    let onClearUnpinned: () -> Void
    let onClearAll: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 14))
                Text("Clipboard History")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onPaste) {
                HStack(spacing: 6) {
                    Text(pasteLabel)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
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
                    Text("Actions")
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
    }

    private var pasteLabel: String {
        if let name = appName {
            return "Paste to \(name)"
        }
        return "Paste"
    }
}

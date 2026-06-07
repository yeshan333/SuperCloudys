import SwiftUI

struct BottomBarView: View {
    let appName: String?
    let onPaste: () -> Void
    let onActions: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .foregroundColor(.red)
            Text("Clipboard History")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Spacer()

            Button(action: onPaste) {
                HStack(spacing: 4) {
                    Text(pasteLabel)
                        .font(.system(size: 12))
                    Text("↵")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            Divider().frame(height: 16)

            Button(action: onActions) {
                Text("Actions")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)

            HStack(spacing: 2) {
                Text("⌃")
                    .font(.system(size: 11))
                Text("H")
                    .font(.system(size: 11))
            }
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var pasteLabel: String {
        if let name = appName {
            return "Paste to \(name)"
        }
        return "Paste"
    }
}

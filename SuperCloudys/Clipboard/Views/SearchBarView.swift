import SwiftUI

struct SearchBarView: View {
    @Binding var query: String
    @Binding var typeFilter: ClipboardContentType?
    let isVisible: Bool
    let onDismiss: () -> Void
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onDismiss) {
                Image(systemName: "arrow.left")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            TextField("Type to filter entries...", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($isSearchFocused)

            Picker("", selection: $typeFilter) {
                Text("All Types").tag(nil as ClipboardContentType?)
                ForEach(ClipboardContentType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type as ClipboardContentType?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
        .onChange(of: isVisible) { visible in
            if visible {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isSearchFocused = true
                }
            }
        }
    }
}

extension ClipboardContentType {
    var displayName: String {
        switch self {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .url: return "URL"
        case .fileGroup: return "Files"
        case .image: return "Image"
        case .color: return "Color"
        case .unknown: return "Other"
        }
    }

    var iconName: String {
        switch self {
        case .text, .richText: return "doc.text"
        case .url: return "link"
        case .fileGroup: return "folder"
        case .image: return "photo"
        case .color: return "paintpalette"
        case .unknown: return "questionmark.square"
        }
    }
}

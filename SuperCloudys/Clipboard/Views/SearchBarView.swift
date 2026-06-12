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
                Image(systemName: "arrow.left.circle.fill")
                    .font(.system(size: 24))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("Search clipboard...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .regular))
                    .focused($isSearchFocused)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Picker("", selection: $typeFilter) {
                Text("All Types").tag(nil as ClipboardContentType?)
                ForEach(ClipboardContentType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type as ClipboardContentType?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
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

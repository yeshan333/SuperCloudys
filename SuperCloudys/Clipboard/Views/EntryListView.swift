import SwiftUI

struct EntryListView: View {
    let entries: [ClipboardEntry]
    @Binding var selectedID: UUID?
    var searchQuery: String = ""
    var onDoubleClick: ((UUID) -> Void)?
    var onTogglePin: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    @Namespace private var animation

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    let grouped = groupedByDay(entries)
                    ForEach(grouped, id: \.title) { group in
                        Section(header: headerView(title: group.title)) {
                            ForEach(group.entries) { entry in
                                EntryRowView(
                                    entry: entry,
                                    isSelected: selectedID == entry.id,
                                    animation: animation
                                )
                                .id(entry.id)
                                .onTapGesture(count: 2) { onDoubleClick?(entry.id) }
                                .onTapGesture(count: 1) { 
                                    withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8, blendDuration: 0.1)) {
                                        selectedID = entry.id
                                    }
                                }
                                .contextMenu {
                                    Button(entry.isPinned ? "取消固定" : "固定") {
                                        onTogglePin?(entry.id)
                                    }
                                    Button("删除", role: .destructive) {
                                        onDelete?(entry.id)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color.clear)
            .overlay {
                if entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text(searchQuery.isEmpty
                             ? NSLocalizedString("Clipboard is empty", comment: "")
                             : NSLocalizedString("No results for \"\(searchQuery)\"", comment: ""))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
            }
            .onChange(of: selectedID) { id in
                if let id {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(id)
                    }
                }
            }
        }
    }

    private func headerView(title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func groupedByDay(_ entries: [ClipboardEntry]) -> [DayGroup] {
        let calendar = Calendar.current
        var groups: [String: [ClipboardEntry]] = [:]
        var order: [String] = []

        for entry in entries {
            let key = entry.isPinned ? "Pinned" : dayLabel(for: entry.lastUsedAt ?? entry.createdAt, calendar: calendar)
            if groups[key] == nil {
                order.append(key)
                groups[key] = []
            }
            groups[key]?.append(entry)
        }
        return order.map { DayGroup(title: $0, entries: groups[$0] ?? []) }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private func dayLabel(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return Self.dateFormatter.string(from: date)
    }
}

private struct DayGroup {
    let title: String
    let entries: [ClipboardEntry]
}

struct EntryRowView: View {
    let entry: ClipboardEntry
    let isSelected: Bool
    var animation: Namespace.ID

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.contentType.iconName)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? .white : .secondary)
                .frame(width: 16)

            Text(entry.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? .white : .primary)

            Spacer()

            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor)
                    .matchedGeometryEffect(id: "selection", in: animation)
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
            }
        }
    }
}

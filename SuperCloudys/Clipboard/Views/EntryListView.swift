import SwiftUI

struct EntryListView: View {
    let entries: [ClipboardEntry]
    @Binding var selectedID: UUID?
    var onDoubleClick: ((UUID) -> Void)?

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedID) {
                let grouped = groupedByDay(entries)
                ForEach(grouped, id: \.title) { group in
                    Section(header: Text(group.title).font(.caption).foregroundColor(.secondary)) {
                        ForEach(group.entries) { entry in
                            EntryRowView(entry: entry, isSelected: selectedID == entry.id)
                                .tag(entry.id)
                                .onTapGesture(count: 2) { onDoubleClick?(entry.id) }
                                .onTapGesture(count: 1) { selectedID = entry.id }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectedID) { id in
                if let id { withAnimation { proxy.scrollTo(id) } }
            }
        }
    }

    private func groupedByDay(_ entries: [ClipboardEntry]) -> [DayGroup] {
        let calendar = Calendar.current
        var groups: [String: [ClipboardEntry]] = [:]
        var order: [String] = []

        for entry in entries {
            let key = dayLabel(for: entry.createdAt, calendar: calendar)
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

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.contentType.iconName)
                .foregroundColor(.secondary)
                .frame(width: 16)

            Text(entry.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.system(size: 13))

            Spacer()

            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

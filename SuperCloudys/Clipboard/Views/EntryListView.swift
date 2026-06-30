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
                             ? NSLocalizedString("剪切板为空", comment: "")
                             : NSLocalizedString("没有找到 “\(searchQuery)”", comment: ""))
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
            let key = entry.isPinned ? "已固定" : dayLabel(for: entry.lastUsedAt ?? entry.createdAt, calendar: calendar)
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
        f.locale = Locale(identifier: "zh_CN")
        f.dateStyle = .medium
        return f
    }()

    private func dayLabel(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
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
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .matchedGeometryEffect(id: "selection", in: animation)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
                    }
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.accentColor.opacity(0.85))
                            .frame(width: 3)
                            .padding(.vertical, 8)
                    }
            }
        }
    }

    private var subtitle: String {
        [
            entry.sourceAppName ?? "未知来源",
            relativeTime(for: entry.lastUsedAt ?? entry.createdAt),
            entry.contentType.displayName
        ].joined(separator: " · ")
    }

    private func relativeTime(for date: Date) -> String {
        let interval = max(0, Date().timeIntervalSince(date))
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        return Self.shortDateFormatter.string(from: date)
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
}

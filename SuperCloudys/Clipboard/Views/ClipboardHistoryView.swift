import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var controller: ClipboardHistoryController
    let onDismiss: () -> Void

    @State private var selectedID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            SearchBarView(
                query: $controller.searchQuery,
                typeFilter: $controller.typeFilter,
                isVisible: controller.isPanelVisible,
                onDismiss: onDismiss
            )
            Divider()
            HSplitView {
                EntryListView(
                    entries: controller.filteredEntries,
                    selectedID: $selectedID,
                    onDoubleClick: { id in
                        selectedID = id
                        pasteEntry(id: id)
                    }
                )
                .frame(minWidth: 280, maxWidth: 320)

                DetailPanelView(
                    entry: selectedEntry,
                    onPaste: { pasteSelected() },
                    onCopy: { copySelected() }
                )
            }
            Divider()
            BottomBarView(
                appName: selectedEntry?.sourceAppName,
                onPaste: { pasteSelected() },
                onActions: {}
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.clear)
        .onAppear { selectFirst() }
        .onChange(of: controller.filteredEntries) { _ in selectFirst() }
        .onExitCommand { onDismiss() }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            pasteSelected()
            return .handled
        }
    }

    private var selectedEntry: ClipboardEntry? {
        guard let id = selectedID else { return nil }
        return controller.filteredEntries.first { $0.id == id }
    }

    private func selectFirst() {
        if selectedID == nil || !controller.filteredEntries.contains(where: { $0.id == selectedID }) {
            selectedID = controller.filteredEntries.first?.id
        }
    }

    private func pasteSelected() {
        guard let entry = selectedEntry else { return }
        pasteEntry(entry: entry)
    }

    private func pasteEntry(id: UUID) {
        guard let entry = controller.filteredEntries.first(where: { $0.id == id }) else { return }
        pasteEntry(entry: entry)
    }

    private func pasteEntry(entry: ClipboardEntry) {
        onDismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            controller.pasteToFrontApp(entry)
        }
    }

    private func moveSelection(by offset: Int) {
        let entries = controller.filteredEntries
        guard !entries.isEmpty else { return }
        guard let currentID = selectedID,
              let idx = entries.firstIndex(where: { $0.id == currentID }) else {
            selectedID = entries.first?.id
            return
        }
        let newIdx = min(max(entries.startIndex, idx + offset), entries.endIndex - 1)
        selectedID = entries[newIdx].id
    }

    private func copySelected() {
        guard let entry = selectedEntry else { return }
        controller.copyToClipboard(entry)
    }
}

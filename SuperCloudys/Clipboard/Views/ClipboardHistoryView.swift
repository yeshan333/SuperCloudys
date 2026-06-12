import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var controller: ClipboardHistoryController
    let onDismiss: () -> Void

    @State private var selectedID: UUID?
    @State private var returnKeyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            SearchBarView(
                query: $controller.searchQuery,
                typeFilter: $controller.typeFilter,
                isVisible: controller.isPanelVisible,
                onDismiss: onDismiss
            )
            
            Rectangle()
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 1)
            
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
                .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
            }
            
            Rectangle()
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 1)
                
            BottomBarView(
                appName: selectedEntry?.sourceAppName,
                onPaste: { pasteSelected() },
                onActions: {}
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.clear)
        .onAppear {
            selectFirst()
            installReturnKeyMonitor()
        }
        .onDisappear { removeReturnKeyMonitor() }
        .onChange(of: controller.isPanelVisible) { visible in
            if visible { selectedID = controller.filteredEntries.first?.id }
        }
        .onChange(of: controller.filteredEntries) { _ in selectFirst() }
        .onExitCommand { onDismiss() }
        .onKeyPress(.upArrow) {
            withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8, blendDuration: 0.1)) {
                moveSelection(by: -1)
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8, blendDuration: 0.1)) {
                moveSelection(by: 1)
            }
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

    // MARK: - IME-aware Return key handling

    private func installReturnKeyMonitor() {
        returnKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 36 else { return event }
            if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
               textView.hasMarkedText() {
                return event
            }
            pasteSelected()
            return nil
        }
    }

    private func removeReturnKeyMonitor() {
        if let monitor = returnKeyMonitor {
            NSEvent.removeMonitor(monitor)
            returnKeyMonitor = nil
        }
    }
}

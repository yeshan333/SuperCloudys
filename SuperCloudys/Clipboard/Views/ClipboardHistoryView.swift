import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var controller: ClipboardHistoryController
    let onDismiss: () -> Void

    @State private var selectedID: UUID?
    @State private var keyboardMonitor: Any?
    @State private var copyToast: String?

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
                    searchQuery: controller.searchQuery,
                    onDoubleClick: { id in
                        selectedID = id
                        pasteEntry(id: id)
                    },
                    onTogglePin: { id in
                        controller.togglePin(id: id)
                    },
                    onDelete: { id in
                        controller.delete(id: id)
                    }
                )
                .frame(minWidth: 280, maxWidth: 320)

                DetailPanelView(
                    entry: selectedEntry
                )
                .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
            }
            
            Rectangle()
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 1)
                
            BottomBarView(
                appName: selectedEntry?.sourceAppName,
                onPaste: { pasteSelected() },
                onCopy: { copySelected() },
                onClearUnpinned: { controller.clearUnpinned() },
                onClearAll: { controller.clearAll() }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.clear)
        .onAppear {
            selectFirst()
            installKeyboardMonitor()
        }
        .onDisappear { removeKeyboardMonitor() }
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
        .overlay(alignment: .bottom) {
            if let toast = copyToast {
                Text(toast)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .padding(.bottom, 48)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: copyToast)
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
        controller.clearSearch()
        controller.pasteToFrontApp(entry)
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
        controller.clearSearch()
        copyToast = NSLocalizedString("已复制到剪切板", comment: "")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copyToast = nil
        }
    }

    // MARK: - Keyboard handling

    private func installKeyboardMonitor() {
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard controller.isPanelVisible else { return event }

            if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
               textView.hasMarkedText() {
                return event
            }

            switch event.keyCode {
            case 36:
                pasteSelected()
                return nil
            case 48:
                controller.cycleTypeFilter(reverse: event.modifierFlags.contains(.shift))
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
    }
}

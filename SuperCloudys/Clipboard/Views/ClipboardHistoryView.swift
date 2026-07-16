import SwiftUI

enum ClipboardReturnAction: Equatable {
    case copy
    case paste
}

struct ClipboardHistoryView: View {
    @ObservedObject var controller: ClipboardHistoryController
    let onDismiss: () -> Void

    @State private var selectedID: UUID?
    @State private var keyboardMonitor: Any?
    @State private var copyToast: String?
    @State private var showsClearAllConfirmation = false

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
                appName: controller.previousApp?.localizedName,
                canCopy: selectedEntry != nil,
                canPaste: selectedEntry != nil && controller.canPasteToPreviousApp,
                onPaste: { pasteSelected() },
                onCopy: { copySelected() },
                onClearUnpinned: { controller.clearUnpinned() },
                onClearAll: { showsClearAllConfirmation = true }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.clear)
        .onAppear {
            selectFirst()
            installKeyboardMonitor()
        }
        .onDisappear { removeKeyboardMonitor() }
        .onChange(of: controller.isPanelVisible) { _, visible in
            if visible { selectedID = controller.filteredEntries.first?.id }
        }
        .onChange(of: controller.filteredEntries) { selectFirst() }
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
        .alert("清空所有剪贴板历史？", isPresented: $showsClearAllConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { controller.clearAll() }
        } message: {
            Text("固定条目和图片文件也会被永久删除。")
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
        guard AccessibilityActivator.isTrusted else {
            showToast("请先授予辅助功能权限")
            return
        }
        guard controller.previousApp?.isTerminated == false else {
            showToast("未找到可粘贴的目标应用")
            return
        }
        onDismiss()
        controller.clearSearch()
        Task { @MainActor in
            guard await controller.pasteToFrontApp(entry) else {
                ClipboardPanelController.shared.show()
                showToast("粘贴失败，目标应用未能激活")
                return
            }
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
        Task { @MainActor in
            guard await controller.copyToClipboard(entry) else {
                showToast("复制失败，原始内容可能已不存在")
                return
            }
            controller.clearSearch()
            showToast(NSLocalizedString("已复制到剪贴板", comment: ""))
        }
    }

    private func showToast(_ message: String) {
        copyToast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copyToast == message { copyToast = nil }
        }
    }

    // MARK: - Keyboard handling

    private func installKeyboardMonitor() {
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard controller.isPanelVisible else { return event }

            let textView = NSApp.keyWindow?.firstResponder as? NSTextView
            if textView?.hasMarkedText() == true {
                return event
            }

            switch event.keyCode {
            case 36:
                switch Self.returnAction(for: event.modifierFlags) {
                case .copy: copySelected()
                case .paste: pasteSelected()
                }
                return nil
            case 48:
                controller.cycleTypeFilter(reverse: event.modifierFlags.contains(.shift))
                return nil
            case 8 where event.modifierFlags.contains(.command):
                if textView?.selectedRange().length ?? 0 > 0 { return event }
                copySelected()
                return nil
            case 47 where event.modifierFlags.contains(.command):
                if let id = selectedID { controller.togglePin(id: id) }
                return nil
            case 51 where event.modifierFlags.contains(.command):
                if textView != nil { return event }
                if let id = selectedID { controller.delete(id: id) }
                return nil
            default:
                return event
            }
        }
    }

    static func returnAction(for modifierFlags: NSEvent.ModifierFlags) -> ClipboardReturnAction {
        modifierFlags.contains(.command) ? .paste : .copy
    }

    private func removeKeyboardMonitor() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
    }
}

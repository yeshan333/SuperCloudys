import AppKit
import SwiftUI

@MainActor
final class ClipboardPanelController {

    static let shared = ClipboardPanelController()

    private var panel: NSPanel?
    private let historyController = ClipboardHistoryController.shared

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        historyController.rememberFrontmostApp()

        if panel == nil {
            createPanel()
        }
        guard let panel else { return }

        NSApp.setActivationPolicy(.regular)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        historyController.isPanelVisible = true
    }

    func hide() {
        historyController.isPanelVisible = false
        panel?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Private

    private func createPanel() {
        let contentView = ClipboardHistoryView(controller: historyController) { [weak self] in
            self?.hide()
        }
        let hostingView = NSHostingView(rootView: contentView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let visualEffect = NSVisualEffectView(frame: panel.contentView!.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true

        panel.contentView?.addSubview(visualEffect)
        hostingView.frame = panel.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hostingView)

        self.panel = panel
    }
}

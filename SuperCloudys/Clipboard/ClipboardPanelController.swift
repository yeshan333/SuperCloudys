import AppKit
import SwiftUI

@MainActor
final class ClipboardPanelController {

    static let shared = ClipboardPanelController()

    private var panel: NSPanel?
    private var resignObserver: NSObjectProtocol?
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

        position(panel, near: NSEvent.mouseLocation)
        panel.makeKeyAndOrderFront(nil)
        
        historyController.isPanelVisible = true
    }

    func hide() {
        historyController.isPanelVisible = false
        panel?.orderOut(nil)
    }

    // MARK: - Private

    private func createPanel() {
        let contentView = ClipboardHistoryView(controller: historyController) { [weak self] in
            self?.hide()
        }
        let hostingView = NSHostingView(rootView: contentView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
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
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 20
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 1
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor

        panel.contentView?.addSubview(visualEffect)
        hostingView.frame = panel.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hostingView)

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }

        self.panel = panel
    }

    private func position(_ panel: NSPanel, near point: NSPoint) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
            ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = panel.frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = min(max(point.x, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(point.y - frame.height, visible.minY), visible.maxY - frame.height)
        panel.setFrame(frame, display: false)
    }
}

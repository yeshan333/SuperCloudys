import AppKit
import SwiftUI

struct InputSourceIndicatorContent: Equatable {
    let source: KeyboardInputSource
    let bundleID: String
    let appName: String
    let appPath: String?
}

@MainActor
protocol InputSourceIndicatorPresenting: AnyObject {
    func show(_ content: InputSourceIndicatorContent)
    func hide()
}

/// 只显示状态，不接收键盘或鼠标事件，也不激活 SuperCloudys。
@MainActor
final class InputSourceIndicatorController: InputSourceIndicatorPresenting {
    static let shared = InputSourceIndicatorController()
    private(set) var panel: NSPanel?
    private var dismissal: Task<Void, Never>?
    private var mouseMonitor: Any?
    private let sourceService = SystemInputSourceService()
    private let icons = NSCache<NSString, NSImage>()
    private let settings: InputSourceSettings

    init(settings: InputSourceSettings = InputSourceSettings()) {
        self.settings = settings
    }

    func show(_ content: InputSourceIndicatorContent) {
        dismissal?.cancel()
        let panel = self.panel ?? createPanel()
        let style = settings.indicatorStyle(for: content.source.id)
        let background = Self.color(hex: style.backgroundHex) ?? Self.color(hex: "000000d1")!
        let foreground = Self.color(hex: style.foregroundHex) ?? .white
        panel.contentView?.layer?.backgroundColor = background.cgColor
        let view = InputSourceIndicatorView(
            content: content, icon: icon(for: content.source.id),
            foreground: foreground, background: background
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: panel.frame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView?.subviews.filter { $0 is NSHostingView<InputSourceIndicatorView> }
            .forEach { $0.removeFromSuperview() }
        panel.contentView?.addSubview(hosting)
        position(panel, near: NSEvent.mouseLocation)
        panel.orderFrontRegardless()
        trackMouseWhileVisible()
        dismissal = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(800)) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        dismissal?.cancel()
        dismissal = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        panel?.orderOut(nil)
    }

    private func icon(for id: InputSourceIdentifier) -> NSImage? {
        let key = "\(id.sourceID)::\(id.modeID ?? "")" as NSString
        if let cached = icons.object(forKey: key) { return cached }
        guard let image = sourceService.icon(for: id) else { return nil }
        icons.countLimit = 64
        icons.setObject(image, forKey: key)
        return image
    }

    private func trackMouseWhileVisible() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.isVisible else { return }
                self.position(panel, near: NSEvent.mouseLocation)
            }
        }
    }

    private func createPanel() -> NSPanel {
        let panel = InputSourceIndicatorPanel(
            contentRect: NSRect(x: 0, y: 0, width: 28, height: 28),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.setAccessibilityElement(true)
        panel.setAccessibilityRole(.group)

        let background = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        background.layer?.cornerRadius = 5
        background.layer?.masksToBounds = true
        panel.contentView = background
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel, near point: NSPoint) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
            ?? NSScreen.main else { return }
        panel.setFrameOrigin(Self.origin(near: point, size: panel.frame.size, visibleFrame: screen.visibleFrame))
    }

    static func origin(near point: NSPoint, size: NSSize, visibleFrame: NSRect) -> NSPoint {
        let visible = visibleFrame.insetBy(dx: 4, dy: 4)
        return NSPoint(
            x: min(max(point.x + 9, visible.minX), visible.maxX - size.width),
            y: min(max(point.y - size.height - 9, visible.minY), visible.maxY - size.height)
        )
    }

    static func color(hex: String) -> NSColor? {
        guard hex.count == 8, let value = UInt32(hex, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((value >> 24) & 255) / 255,
            green: CGFloat((value >> 16) & 255) / 255,
            blue: CGFloat((value >> 8) & 255) / 255,
            alpha: CGFloat(value & 255) / 255
        )
    }
}

private final class InputSourceIndicatorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct InputSourceIndicatorView: View {
    let content: InputSourceIndicatorContent
    let icon: NSImage?
    let foreground: NSColor
    let background: NSColor

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .renderingMode(icon.isTemplate ? .template : .original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Color(nsColor: foreground))
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: foreground))
                    .frame(width: 18, height: 18)
                    .overlay {
                        // ABC 对应 A；未知输入法仍保持一个小标记，不展开名称。
                        Text(String(content.source.name.prefix(1)).uppercased())
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Color(nsColor: background))
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(content.appName)，当前输入法：\(content.source.name)")
    }
}

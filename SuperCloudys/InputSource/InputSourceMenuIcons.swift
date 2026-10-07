import AppKit

/// 原生菜单只接受一张图片，先绘制带配色的输入法标记，再与应用图标合成。
@MainActor
final class InputSourceMenuIcons {
    static let shared = InputSourceMenuIcons()
    private let service = SystemInputSourceService()
    private let settings = InputSourceSettings()
    private let cache = NSCache<NSString, NSImage>()

    func icon(for source: KeyboardInputSource) -> NSImage {
        let style = settings.indicatorStyle(for: source.id)
        let key = "\(source.id.styleKey)|\(source.name)|\(style.backgroundHex)|\(style.foregroundHex)" as NSString
        if let image = cache.object(forKey: key) { return image }
        let image = Self.badge(name: source.name, icon: service.icon(for: source.id), style: style)
        cache.countLimit = 64
        cache.setObject(image, forKey: key)
        return image
    }

    static func badge(name: String, icon: NSImage?, style: InputSourceIndicatorStyle) -> NSImage {
        let background = InputSourceIndicatorController.color(hex: style.backgroundHex)
            ?? InputSourceIndicatorController.color(hex: InputSourceIndicatorStyle.standard.backgroundHex)!
        let foreground = InputSourceIndicatorController.color(hex: style.foregroundHex) ?? .white
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { bounds in
            background.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).fill()
            let inset = bounds.insetBy(dx: 3, dy: 3)
            if let icon {
                let context = NSGraphicsContext.current?.cgContext
                context?.beginTransparencyLayer(auxiliaryInfo: nil)
                icon.draw(in: inset, from: .zero, operation: .sourceOver, fraction: 1)
                if icon.isTemplate {
                    foreground.setFill()
                    inset.fill(using: .sourceIn)
                }
                context?.endTransparencyLayer()
            } else {
                foreground.setFill()
                NSBezierPath(roundedRect: inset, xRadius: 2, yRadius: 2).fill()
                let letter = String(name.prefix(1)).uppercased() as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10), .foregroundColor: background
                ]
                let size = letter.size(withAttributes: attributes)
                letter.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                            withAttributes: attributes)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    static func applicationIcon(_ appIcon: NSImage, sourceIcon: NSImage) -> NSImage {
        let image = NSImage(size: NSSize(width: 40, height: 18), flipped: false) { _ in
            appIcon.draw(in: NSRect(x: 0, y: 1, width: 16, height: 16))
            sourceIcon.draw(in: NSRect(x: 22, y: 0, width: 18, height: 18))
            return true
        }
        image.isTemplate = false
        return image
    }
}

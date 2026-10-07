import AppKit
import Carbon
import Foundation

struct KeyboardInputSource: Identifiable, Equatable, Sendable {
    let id: InputSourceIdentifier
    let name: String
}

@MainActor
protocol InputSourceService {
    func availableSources() -> [KeyboardInputSource]
    func currentSourceID() -> InputSourceIdentifier?
    /// 返回系统错误码；0 表示选择成功。
    func select(_ identifier: InputSourceIdentifier) -> Int32
}

@MainActor
final class SystemInputSourceService: InputSourceService {
    func availableSources() -> [KeyboardInputSource] {
        var seen = Set<InputSourceIdentifier>()
        return selectableSources().compactMap { source in
            guard let id = identifier(of: source),
                  let name = property(source, kTISPropertyLocalizedName) as? String,
                  seen.insert(id).inserted else { return nil }
            return KeyboardInputSource(id: id, name: name)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func currentSourceID() -> InputSourceIdentifier? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return identifier(of: source)
    }

    func select(_ identifier: InputSourceIdentifier) -> Int32 {
        guard let source = selectableSources().first(where: { self.identifier(of: $0) == identifier })
        else { return Int32(paramErr) }
        return TISSelectInputSource(source)
    }

    /// 读取输入法自己的菜单栏图标；没有图标资源的键盘布局由提示视图显示单字标记。
    func icon(for identifier: InputSourceIdentifier) -> NSImage? {
        guard let source = selectableSources().first(where: { self.identifier(of: $0) == identifier }),
              let url = property(source, kTISPropertyIconImageURL) as? URL,
              let image = NSImage(contentsOf: url.absoluteURL) else { return nil }
        return Self.prepareIcon(image, from: url)
    }

    /// PDF 也可能包含彩色内容，只有单色 PDF 才按提示文字颜色绘制。
    static func prepareIcon(_ image: NSImage, from url: URL) -> NSImage {
        image.isTemplate = false
        guard url.pathExtension.lowercased() == "pdf",
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
              ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return image }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
        NSGraphicsContext.restoreGraphicsState()
        for y in 0..<32 {
            for x in 0..<32 {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.05 else { continue }
                if abs(color.redComponent - color.greenComponent) > 0.03
                    || abs(color.greenComponent - color.blueComponent) > 0.03 {
                    return image
                }
            }
        }
        image.isTemplate = true
        return image
    }

    private func selectableSources() -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource]
        else { return [] }
        return list.filter {
            property($0, kTISPropertyInputSourceCategory) as? String == kTISCategoryKeyboardInputSource as String
                && property($0, kTISPropertyInputSourceIsSelectCapable) as? Bool == true
                && property($0, kTISPropertyInputSourceIsEnabled) as? Bool == true
        }
    }

    private func identifier(of source: TISInputSource) -> InputSourceIdentifier? {
        guard let id = property(source, kTISPropertyInputSourceID) as? String else { return nil }
        return InputSourceIdentifier(
            sourceID: id, modeID: property(source, kTISPropertyInputModeID) as? String
        )
    }

    private func property(_ source: TISInputSource, _ key: CFString) -> AnyObject? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
    }
}

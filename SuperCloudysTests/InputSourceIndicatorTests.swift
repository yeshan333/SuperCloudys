import AppKit
import XCTest
@testable import SuperCloudys

final class InputSourceIndicatorTests: XCTestCase {
    @MainActor
    func testCompactSourceIconAppearsBesidePointerWithoutTakingFocusOrClicksAndDisappears() async throws {
        guard ProcessInfo.processInfo.environment["SUPERCLOUDYS_INDICATOR_SMOKE"] == "1" else {
            throw XCTSkip("设置 SUPERCLOUDYS_INDICATOR_SMOKE=1 才显示真实提示浮层")
        }
        let previousPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let sources = SystemInputSourceService().availableSources()
        let source = try XCTUnwrap(sources.first { $0.id.sourceID.contains("sogou") } ?? sources.first)
        let suite = "InputSourceIndicatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let settings = InputSourceSettings(defaults: defaults)
        settings.indicatorStyles = [source.id.styleKey: InputSourceIndicatorStyle(
            backgroundHex: "0c7489ff", foregroundHex: "ffffffff"
        )]
        let controller = InputSourceIndicatorController(settings: settings)
        defer {
            controller.hide()
            defaults.removePersistentDomain(forName: suite)
        }
        controller.show(InputSourceIndicatorContent(
            source: source, bundleID: "test.browser", appName: "Google Chrome", appPath: nil
        ))
        let panel = try XCTUnwrap(controller.panel)
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.frame.size, NSSize(width: 28, height: 28))
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, previousPID)
        let content = try XCTUnwrap(panel.contentView)
        let background = try XCTUnwrap(content.layer?.backgroundColor?.components)
        XCTAssertEqual(background[0], 12.0 / 255, accuracy: 0.001)
        XCTAssertEqual(background[1], 116.0 / 255, accuracy: 0.001)
        XCTAssertEqual(background[2], 137.0 / 255, accuracy: 0.001)
        content.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: "/tmp/SuperCloudys-input-source-indicator.png"))
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertFalse(panel.isVisible)

        let english = try XCTUnwrap(sources.first { $0.id.sourceID == "com.apple.keylayout.ABC" })
        controller.show(InputSourceIndicatorContent(
            source: english, bundleID: "test.editor", appName: "Visual Studio Code", appPath: nil
        ))
        content.layoutSubtreeIfNeeded()
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let englishData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try englishData.write(to: URL(fileURLWithPath: "/tmp/SuperCloudys-input-source-indicator-ABC.png"))
    }

    @MainActor
    func testIconStaysBesidePointerAndInsideDisplayAtScreenEdges() {
        let screen = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
        let size = NSSize(width: 28, height: 28)
        let point = NSPoint(x: -800, y: 500)
        let origin = InputSourceIndicatorController.origin(near: point, size: size, visibleFrame: screen)
        XCTAssertEqual(origin, NSPoint(x: -791, y: 463))
        for point in [
            NSPoint(x: screen.minX, y: screen.minY), NSPoint(x: screen.maxX, y: screen.minY),
            NSPoint(x: screen.minX, y: screen.maxY), NSPoint(x: screen.maxX, y: screen.maxY)
        ] {
            let origin = InputSourceIndicatorController.origin(near: point, size: size, visibleFrame: screen)
            XCTAssertTrue(screen.contains(NSRect(origin: origin, size: size)))
        }
    }

    func testReloadedInputModeColorsTakePrecedenceOverLegacySourceColors() throws {
        let suite = "InputSourceColorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = InputSourceSettings(defaults: defaults)
        let source = InputSourceIdentifier(sourceID: "test.sogou", modeID: "pinyin")
        let legacy = InputSourceIndicatorStyle(backgroundHex: "fffffff2", foregroundHex: "000000ff")
        let mode = InputSourceIndicatorStyle(backgroundHex: "0c7489ff", foregroundHex: "ffffffff")
        settings.indicatorStyles = [source.sourceID: legacy, source.styleKey: mode]
        let restored = InputSourceSettings(defaults: defaults)
        XCTAssertEqual(restored.indicatorStyle(for: source), mode)
        XCTAssertEqual(restored.indicatorStyle(for: InputSourceIdentifier(
            sourceID: source.sourceID, modeID: "another"
        )), legacy)
        XCTAssertEqual(restored.indicatorStyle(for: InputSourceIdentifier(
            sourceID: "unknown", modeID: nil
        )), .standard)
    }

    @MainActor
    func testColoredPdfIconPreservesOriginalColorsInsteadOfUsingForegroundTint() {
        let image = NSImage(size: NSSize(width: 24, height: 24))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 12, height: 24).fill()
        NSColor.blue.setFill()
        NSRect(x: 12, y: 0, width: 12, height: 24).fill()
        image.unlockFocus()
        let prepared = SystemInputSourceService.prepareIcon(image, from: URL(fileURLWithPath: "/icon.pdf"))
        XCTAssertFalse(prepared.isTemplate)
    }

    @MainActor
    func testMonochromePdfIconCanUseTheConfiguredForegroundTint() {
        let image = NSImage(size: NSSize(width: 24, height: 24))
        image.lockFocus()
        NSColor.black.setFill()
        NSRect(x: 4, y: 4, width: 16, height: 16).fill()
        image.unlockFocus()
        let prepared = SystemInputSourceService.prepareIcon(image, from: URL(fileURLWithPath: "/icon.pdf"))
        XCTAssertTrue(prepared.isTemplate)
    }

    @MainActor
    func testMenuInputSourceWithMonochromeIconUsesConfiguredBackgroundAndForegroundColors() throws {
        let icon = NSImage(size: NSSize(width: 12, height: 12))
        icon.lockFocus()
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: 12, height: 12).fill()
        icon.unlockFocus()
        icon.isTemplate = true
        let image = InputSourceMenuIcons.badge(name: "搜狗拼音", icon: icon, style: InputSourceIndicatorStyle(
            backgroundHex: "0c7489ff", foregroundHex: "ffffffff"
        ))
        XCTAssertFalse(image.isTemplate)
        let bitmap = try menuIconBitmap(image)
        let background = try XCTUnwrap(bitmap.colorAt(x: 1, y: 9)?.usingColorSpace(.sRGB))
        let swatch = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { bounds in
            InputSourceIndicatorController.color(hex: "0c7489ff")!.setFill()
            bounds.fill()
            return true
        }
        let expectedBackground = try XCTUnwrap(menuIconBitmap(swatch).colorAt(x: 9, y: 9)?.usingColorSpace(.sRGB))
        XCTAssertEqual(background.redComponent, expectedBackground.redComponent, accuracy: 0.01)
        XCTAssertEqual(background.greenComponent, expectedBackground.greenComponent, accuracy: 0.01)
        XCTAssertEqual(background.blueComponent, expectedBackground.blueComponent, accuracy: 0.01)
        let foreground = try XCTUnwrap(bitmap.colorAt(x: 9, y: 9)?.usingColorSpace(.sRGB))
        XCTAssertEqual(foreground.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(foreground.greenComponent, 1, accuracy: 0.01)
        XCTAssertEqual(foreground.blueComponent, 1, accuracy: 0.01)
    }

    @MainActor
    func testMenuInputSourceWithColoredIconKeepsOriginalColorAndApplicationIconBesideIt() throws {
        let icon = NSImage(size: NSSize(width: 12, height: 12))
        icon.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 12, height: 12).fill()
        icon.unlockFocus()
        let source = InputSourceMenuIcons.badge(name: "彩色输入法", icon: icon, style: .standard)
        let app = NSImage(size: NSSize(width: 16, height: 16))
        app.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        app.unlockFocus()
        let combined = InputSourceMenuIcons.applicationIcon(app, sourceIcon: source)
        XCTAssertFalse(combined.isTemplate)
        let bitmap = try menuIconBitmap(combined)
        let appColor = try XCTUnwrap(bitmap.colorAt(x: 8, y: 9)?.usingColorSpace(.sRGB))
        let sourceColor = try XCTUnwrap(bitmap.colorAt(x: 31, y: 9)?.usingColorSpace(.sRGB))
        let originalApp = try XCTUnwrap(menuIconBitmap(app).colorAt(x: 8, y: 8)?.usingColorSpace(.sRGB))
        let originalSource = try XCTUnwrap(menuIconBitmap(icon).colorAt(x: 6, y: 6)?.usingColorSpace(.sRGB))
        XCTAssertEqual(appColor.blueComponent, originalApp.blueComponent, accuracy: 0.01)
        XCTAssertEqual(appColor.redComponent, originalApp.redComponent, accuracy: 0.01)
        XCTAssertEqual(sourceColor.redComponent, originalSource.redComponent, accuracy: 0.01)
        XCTAssertEqual(sourceColor.greenComponent, originalSource.greenComponent, accuracy: 0.01)
        XCTAssertEqual(sourceColor.blueComponent, originalSource.blueComponent, accuracy: 0.01)
    }

    @MainActor
    func testEnabledInputSourcesHaveColoredIconsInNativeConfigurationPicker() throws {
        let sources = SystemInputSourceService().availableSources()
        XCTAssertFalse(sources.isEmpty)
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        picker.addItems(withTitles: sources.map(\.name))
        for (item, source) in zip(picker.itemArray, sources) {
            item.image = InputSourceMenuIcons.shared.icon(for: source)
            XCTAssertFalse(try XCTUnwrap(item.image).isTemplate)
            XCTAssertEqual(item.image?.size, NSSize(width: 18, height: 18))
        }
        let preview = NSImage(size: NSSize(width: 300, height: CGFloat(sources.count) * 30))
        preview.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: preview.size).fill()
        for (index, source) in sources.enumerated() {
            let y = preview.size.height - CGFloat(index + 1) * 30 + 6
            picker.item(at: index)?.image?.draw(in: NSRect(x: 8, y: y, width: 18, height: 18))
            (source.name as NSString).draw(at: NSPoint(x: 34, y: y), withAttributes: [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor
            ])
        }
        preview.unlockFocus()
        let data = try XCTUnwrap(menuIconBitmap(preview).representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: "/tmp/SuperCloudys-input-source-menu-icons.png"))
    }

    @MainActor
    private func menuIconBitmap(_ image: NSImage) throws -> NSBitmapImageRep {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: Int(image.size.width), height: Int(image.size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        let cgImage = try XCTUnwrap(context.makeImage())
        return NSBitmapImageRep(cgImage: cgImage)
    }
}

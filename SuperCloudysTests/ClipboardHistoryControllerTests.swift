import AppKit
import XCTest
@testable import SuperCloudys

final class ClipboardHistoryControllerTests: XCTestCase {

    @MainActor
    func testCopyImagePathWhenFileExistsWritesFullPathAsTextAndMarksEntryUsed() throws {
        try withImagePathFixture { controller, store, pasteboard, directory in
            let path = directory.appendingPathComponent("图片 with spaces.png").path
            try Data([1, 2, 3]).write(to: URL(fileURLWithPath: path))
            let entry = imageEntry(path: path)
            store.insert(entry)

            XCTAssertTrue(controller.copyImagePathToClipboard(entry, pasteboard: pasteboard))
            XCTAssertEqual(pasteboard.string(forType: .string), path)
            XCTAssertNil(pasteboard.data(forType: .png))
            XCTAssertNotNil(store.allEntries.first?.lastUsedAt)
        }
    }

    @MainActor
    func testCopyImagePathWhenFileIsUnavailablePreservesClipboardAndUsage() throws {
        try withImagePathFixture { controller, store, pasteboard, directory in
            pasteboard.setString("已有剪贴板内容", forType: .string)
            let originalChangeCount = pasteboard.changeCount
            for path in [nil, "", directory.appendingPathComponent("missing.png").path, directory.path] {
                let entry = imageEntry(path: path)
                store.insert(entry)

                XCTAssertFalse(controller.copyImagePathToClipboard(entry, pasteboard: pasteboard))
                XCTAssertEqual(pasteboard.string(forType: .string), "已有剪贴板内容")
                XCTAssertEqual(pasteboard.changeCount, originalChangeCount)
                XCTAssertNil(store.allEntries.first?.lastUsedAt)
            }
        }
    }

    @MainActor
    private func withImagePathFixture(
        _ body: (ClipboardHistoryController, ClipboardStore, NSPasteboard, URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardImagePathTests_\(UUID().uuidString)")
        let suiteName = "ClipboardImagePathTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = ClipboardSettings(defaults: defaults)
        let store = ClipboardStore(storageDirectory: directory)
        let monitor = ClipboardMonitorService(settings: settings)
        let controller = ClipboardHistoryController(store: store, monitor: monitor, settings: settings)
        let pasteboard = NSPasteboard.withUniqueName()
        defer {
            monitor.stop()
            store.flush()
            pasteboard.releaseGlobally()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(controller, store, pasteboard, directory)
    }

    private func imageEntry(path: String?) -> ClipboardEntry {
        ClipboardEntry(
            id: UUID(), contentType: .image, plainText: nil,
            title: "图片", subtitle: nil, createdAt: Date(),
            sourceAppBundleID: nil, sourceAppName: nil,
            isPinned: false, lastUsedAt: nil, fingerprint: UUID().uuidString,
            imagePath: path, thumbnailPath: nil, filePaths: nil, colorHex: nil
        )
    }

    @MainActor
    func testReturnCopiesUnlessCommandIsHeld() {
        XCTAssertEqual(ClipboardHistoryView.returnAction(for: []), .copy)
        XCTAssertEqual(ClipboardHistoryView.returnAction(for: [.command]), .paste)
    }

    @MainActor
    func testCycleTypeFilterWrapsForwardAndBackward() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryControllerTests_\(UUID().uuidString)")
        let suiteName = "ClipboardHistoryControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = ClipboardSettings(defaults: defaults)
        let store = ClipboardStore(maxEntries: 10, storageDirectory: tempDir)
        let monitor = ClipboardMonitorService(settings: settings)
        let controller = ClipboardHistoryController(
            store: store, monitor: monitor, settings: settings
        )
        defer {
            monitor.stop()
            store.flush()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempDir)
        }

        XCTAssertNil(controller.typeFilter)

        controller.cycleTypeFilter()
        XCTAssertEqual(controller.typeFilter, .text)

        for _ in ClipboardContentType.filterCases.dropFirst() {
            controller.cycleTypeFilter()
        }
        XCTAssertEqual(controller.typeFilter, .color)

        controller.cycleTypeFilter()
        XCTAssertNil(controller.typeFilter)

        controller.cycleTypeFilter(reverse: true)
        XCTAssertEqual(controller.typeFilter, .color)
    }
}

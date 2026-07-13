import XCTest
@testable import SuperCloudys

final class ClipboardHistoryControllerTests: XCTestCase {

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

import XCTest
@testable import SuperCloudys

@MainActor
final class ClipboardHistoryControllerTests: XCTestCase {

    private var tempDir: URL!
    private var store: ClipboardStore!
    private var settings: ClipboardSettings!
    private var monitor: ClipboardMonitorService!
    private var controller: ClipboardHistoryController!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryControllerTests_\(UUID().uuidString)")
        settings = ClipboardSettings()
        store = ClipboardStore(maxEntries: 10, storageDirectory: tempDir)
        monitor = ClipboardMonitorService(settings: settings)
        controller = ClipboardHistoryController(store: store, monitor: monitor, settings: settings)
    }

    override func tearDown() {
        monitor.stop()
        try? FileManager.default.removeItem(at: tempDir)
        controller = nil
        monitor = nil
        store = nil
        settings = nil
        super.tearDown()
    }

    func testCycleTypeFilterWrapsForwardAndBackward() {
        XCTAssertNil(controller.typeFilter)

        controller.cycleTypeFilter()
        XCTAssertEqual(controller.typeFilter, .text)

        for _ in ClipboardContentType.allCases.dropFirst() {
            controller.cycleTypeFilter()
        }
        XCTAssertEqual(controller.typeFilter, .unknown)

        controller.cycleTypeFilter()
        XCTAssertNil(controller.typeFilter)

        controller.cycleTypeFilter(reverse: true)
        XCTAssertEqual(controller.typeFilter, .unknown)
    }
}

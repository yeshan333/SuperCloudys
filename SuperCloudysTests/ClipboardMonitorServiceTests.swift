import XCTest
@testable import SuperCloudys

final class ClipboardMonitorServiceTests: XCTestCase {

    func testDetectedWebURLRecognizesPlainHTTPSText() {
        let monitor = makeMonitor()

        let url = monitor.detectedWebURL(in: "https://example.com/path?q=1")

        XCTAssertEqual(url?.absoluteString, "https://example.com/path?q=1")
    }

    func testDetectedWebURLRejectsMixedPlainText() {
        let monitor = makeMonitor()

        let url = monitor.detectedWebURL(in: "see https://example.com/path?q=1")

        XCTAssertNil(url)
    }

    func testSelfWriteSuppressionOnlyMatchesExactChangeCount() {
        let monitor = makeMonitor()

        monitor.markSelfWrite(changeCount: 10)
        XCTAssertFalse(monitor.consumeSuppressedChangeCount(11))

        monitor.markSelfWrite(changeCount: 12)
        XCTAssertTrue(monitor.consumeSuppressedChangeCount(12))
        XCTAssertFalse(monitor.consumeSuppressedChangeCount(12))
    }

    func testRecentlySwitchedExcludedAppIsStillProtected() {
        let monitor = makeMonitor()

        XCTAssertTrue(monitor.shouldExclude(
            sourceBundleID: "com.apple.Safari",
            previousBundleID: "com.1password.1password",
            secondsSinceSwitch: 0.5
        ))
        XCTAssertFalse(monitor.shouldExclude(
            sourceBundleID: "com.apple.Safari",
            previousBundleID: "com.1password.1password",
            secondsSinceSwitch: 1
        ))
    }

    private func makeMonitor() -> ClipboardMonitorService {
        let defaults = UserDefaults(suiteName: "ClipboardMonitorServiceTests.\(UUID().uuidString)")!
        return ClipboardMonitorService(settings: ClipboardSettings(defaults: defaults))
    }
}

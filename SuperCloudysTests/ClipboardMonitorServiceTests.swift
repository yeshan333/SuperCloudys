import XCTest
@testable import SuperCloudys

final class ClipboardMonitorServiceTests: XCTestCase {

    func testDetectedWebURLRecognizesPlainHTTPSText() {
        let monitor = ClipboardMonitorService(settings: ClipboardSettings())

        let url = monitor.detectedWebURL(in: "https://example.com/path?q=1")

        XCTAssertEqual(url?.absoluteString, "https://example.com/path?q=1")
    }

    func testDetectedWebURLRejectsMixedPlainText() {
        let monitor = ClipboardMonitorService(settings: ClipboardSettings())

        let url = monitor.detectedWebURL(in: "see https://example.com/path?q=1")

        XCTAssertNil(url)
    }
}

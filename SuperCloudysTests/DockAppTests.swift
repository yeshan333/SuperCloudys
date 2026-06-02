import XCTest
@testable import SuperCloudys

final class DockAppTests: XCTestCase {

    func testShortcutLabelFor1Through9() {
        for index in 0...8 {
            XCTAssertEqual(
                DockApp.shortcutLabel(forIndex: index),
                String(index + 1),
                "Index \(index) should map to label '\(index + 1)'"
            )
        }
    }

    func testShortcutLabelFor10thAppIsZero() {
        XCTAssertEqual(DockApp.shortcutLabel(forIndex: 9), "0")
    }

    func testShortcutLabelOutOfRange() {
        XCTAssertNil(DockApp.shortcutLabel(forIndex: 10))
        XCTAssertNil(DockApp.shortcutLabel(forIndex: 100))
        XCTAssertNil(DockApp.shortcutLabel(forIndex: -1))
    }

    func testMaxShortcutAppsConstant() {
        XCTAssertEqual(DockApp.maxShortcutApps, 10)
    }
}

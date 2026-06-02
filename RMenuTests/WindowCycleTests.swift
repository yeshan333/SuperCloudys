import XCTest
@testable import RMenu

final class WindowCycleTests: XCTestCase {

    // MARK: - AccessibilityActivator guards

    func testWindowCountReturnsZeroWhenNotTrusted() {
        // pid 1 (launchd) — we never have AX trust in test runner
        let count = AccessibilityActivator.windowCount(pid: 1)
        XCTAssertEqual(count, 0)
    }

    func testCycleWindowsReturnsFalseWhenNotTrusted() {
        let result = AccessibilityActivator.cycleWindows(pid: 1)
        XCTAssertFalse(result)
    }

    func testActivateReturnsFalseWhenNotTrusted() {
        let result = AccessibilityActivator.activate(pid: 1)
        XCTAssertFalse(result)
    }

    // MARK: - DockAppLauncher toggle (non-running apps)

    func testToggleNonRunningAppDoesNotCrash() {
        // A bundleID that doesn't exist won't crash
        DockAppLauncher.toggle(bundleID: "com.example.nonexistent.test")
    }

    func testToggleWithInvalidPathDoesNotCrash() {
        DockAppLauncher.toggle(
            bundleID: "com.example.nonexistent.test",
            appPath: "/nonexistent/path/App.app"
        )
    }
}

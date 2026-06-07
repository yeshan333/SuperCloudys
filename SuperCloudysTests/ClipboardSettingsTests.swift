import XCTest
@testable import SuperCloudys

final class ClipboardSettingsTests: XCTestCase {

    private var settings: ClipboardSettings!

    override func setUp() {
        super.setUp()
        settings = ClipboardSettings.shared
    }

    func testDefaultExcludedAppsContains1Password() {
        XCTAssertTrue(settings.isAppExcluded("com.1password.1password"))
    }

    func testDefaultExcludedAppsContainsKeychain() {
        XCTAssertTrue(settings.isAppExcluded("com.apple.keychainaccess"))
    }

    func testNonExcludedAppReturnsFalse() {
        XCTAssertFalse(settings.isAppExcluded("com.apple.Safari"))
    }

    func testMaxEntriesDefault() {
        // Clear any previously saved value
        UserDefaults.standard.removeObject(forKey: "clipboard_maxEntries")
        let fresh = ClipboardSettings.shared
        XCTAssertEqual(fresh.maxEntries, 500)
    }
}

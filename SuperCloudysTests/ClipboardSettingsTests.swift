import XCTest
@testable import SuperCloudys

final class ClipboardSettingsTests: XCTestCase {

    private var settings: ClipboardSettings!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ClipboardSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        settings = ClipboardSettings(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        settings = nil
        defaults = nil
        super.tearDown()
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

    func testDefaultExcludedAppCanBeExplicitlyIncluded() {
        var excluded = settings.excludedApps
        excluded.remove("com.apple.keychainaccess")
        settings.excludedApps = excluded

        XCTAssertFalse(settings.isAppExcluded("com.apple.keychainaccess"))
    }

    func testMaxEntriesDefault() {
        // Clear any previously saved value
        XCTAssertEqual(settings.maxEntries, 500)
    }
}

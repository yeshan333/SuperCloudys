import XCTest
@testable import SuperCloudys

final class CustomAppStoreTests: XCTestCase {
    func testLegacyCustomAppWithoutBundleIDStillDecodes() throws {
        let data = Data(#"{"name":"Zed","appPath":"/Applications/Zed.app"}"#.utf8)
        let app = try JSONDecoder().decode(CustomApp.self, from: data)

        XCTAssertEqual(app.name, "Zed")
        XCTAssertNil(app.bundleID)
    }
}

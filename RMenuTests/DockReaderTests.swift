import XCTest
@testable import RMenu

final class DockReaderTests: XCTestCase {

    // MARK: - Happy path

    func testParseThreeAppsAssignsLabels1To3() {
        let data = makePlist(persistentApps: [
            fileTile(label: "Finder", bundleID: "com.apple.finder", path: "/System/Library/CoreServices/Finder.app"),
            fileTile(label: "Safari", bundleID: "com.apple.Safari", path: "/Applications/Safari.app"),
            fileTile(label: "Mail",   bundleID: "com.apple.mail",   path: "/Applications/Mail.app"),
        ])

        let apps = DockReader.parseApps(from: data)

        XCTAssertEqual(apps.count, 3)
        XCTAssertEqual(apps[0].bundleID, "com.apple.finder")
        XCTAssertEqual(apps[0].shortcutLabel, "1")
        XCTAssertEqual(apps[1].shortcutLabel, "2")
        XCTAssertEqual(apps[2].shortcutLabel, "3")
    }

    // MARK: - Regression for bug #1 (spacer/separator tiles)

    func testSpacerTilesDoNotShiftShortcutLabels() {
        let data = makePlist(persistentApps: [
            fileTile(label: "Safari", bundleID: "com.apple.Safari", path: "/Applications/Safari.app"),
            spacerTile(),
            fileTile(label: "Mail",   bundleID: "com.apple.mail",   path: "/Applications/Mail.app"),
            spacerTile(),
            fileTile(label: "Notes",  bundleID: "com.apple.Notes",  path: "/Applications/Notes.app"),
        ])

        let apps = DockReader.parseApps(from: data)

        XCTAssertEqual(apps.count, 3)
        XCTAssertEqual(apps[0].bundleID, "com.apple.Safari")
        XCTAssertEqual(apps[0].shortcutLabel, "1", "Safari should be ⌘1 despite spacer at position 1")
        XCTAssertEqual(apps[1].bundleID, "com.apple.mail")
        XCTAssertEqual(apps[1].shortcutLabel, "2", "Mail should be ⌘2, not ⌘3")
        XCTAssertEqual(apps[2].bundleID, "com.apple.Notes")
        XCTAssertEqual(apps[2].shortcutLabel, "3", "Notes should be ⌘3, not ⌘5")
    }

    // MARK: - Filtering & validation

    func testTilesMissingBundleIDAreFiltered() {
        let data = makePlist(persistentApps: [
            fileTile(label: "Good", bundleID: "com.example.good", path: "/Applications/Good.app"),
            fileTile(label: "Bad",  bundleID: "",                 path: "/Applications/Bad.app"),
            ["tile-type": "file-tile", "tile-data": ["file-label": "NoBundleID"]],
            fileTile(label: "Also Good", bundleID: "com.example.alsogood", path: "/Applications/AlsoGood.app"),
        ])

        let apps = DockReader.parseApps(from: data)

        XCTAssertEqual(apps.count, 2)
        XCTAssertEqual(apps[0].bundleID, "com.example.good")
        XCTAssertEqual(apps[1].bundleID, "com.example.alsogood")
        XCTAssertEqual(apps[1].shortcutLabel, "2")
    }

    func testAppNameFallsBackToBundleIDWhenLabelMissing() {
        let data = makePlist(persistentApps: [
            ["tile-type": "file-tile",
             "tile-data": ["bundle-identifier": "com.example.noname"]],
        ])

        let apps = DockReader.parseApps(from: data)

        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps[0].name, "com.example.noname")
    }

    // MARK: - >10 apps

    func testEleventhAndBeyondHaveNoShortcutLabel() {
        let tiles = (1...12).map { i in
            fileTile(label: "App\(i)", bundleID: "com.example.app\(i)", path: "/Applications/App\(i).app")
        }
        let data = makePlist(persistentApps: tiles)

        let apps = DockReader.parseApps(from: data)

        XCTAssertEqual(apps.count, 12)
        XCTAssertEqual(apps[8].shortcutLabel, "9")
        XCTAssertEqual(apps[9].shortcutLabel, "0")
        XCTAssertNil(apps[10].shortcutLabel)
        XCTAssertNil(apps[11].shortcutLabel)
    }

    // MARK: - URL extraction

    func testAppPathExtractedFromFileURL() {
        let data = makePlist(persistentApps: [
            fileTile(label: "Safari", bundleID: "com.apple.Safari", path: "/Applications/Safari.app"),
        ])

        let apps = DockReader.parseApps(from: data)

        XCTAssertEqual(apps.first?.appPath, "/Applications/Safari.app")
    }

    func testPercentEncodedPathIsDecoded() {
        let tile: [String: Any] = [
            "tile-type": "file-tile",
            "tile-data": [
                "file-label": "My App",
                "bundle-identifier": "com.example.my",
                "file-data": ["_CFURLString": "file:///Applications/My%20App.app"],
            ],
        ]
        let data = makePlist(persistentApps: [tile])

        let apps = DockReader.parseApps(from: data)

        XCTAssertEqual(apps.first?.appPath, "/Applications/My App.app")
    }

    func testNonFileURLReturnsEmptyPath() {
        let tile: [String: Any] = [
            "tile-type": "file-tile",
            "tile-data": [
                "file-label": "Weird",
                "bundle-identifier": "com.example.weird",
                "file-data": ["_CFURLString": "x-coredata://something"],
            ],
        ]
        let data = makePlist(persistentApps: [tile])

        let apps = DockReader.parseApps(from: data)

        XCTAssertEqual(apps.first?.appPath, "")
    }

    // MARK: - Malformed input

    func testEmptyDataReturnsEmptyList() {
        XCTAssertEqual(DockReader.parseApps(from: Data()).count, 0)
    }

    func testMalformedPlistReturnsEmptyList() {
        let garbage = Data("not a plist".utf8)
        XCTAssertEqual(DockReader.parseApps(from: garbage).count, 0)
    }

    func testMissingPersistentAppsKeyReturnsEmptyList() {
        let data = try! PropertyListSerialization.data(
            fromPropertyList: ["some-other-key": "value"],
            format: .xml, options: 0
        )
        XCTAssertEqual(DockReader.parseApps(from: data).count, 0)
    }

    // MARK: - Helpers

    private func makePlist(persistentApps: [[String: Any]]) -> Data {
        let root: [String: Any] = ["persistent-apps": persistentApps]
        return try! PropertyListSerialization.data(
            fromPropertyList: root, format: .xml, options: 0
        )
    }

    private func fileTile(label: String, bundleID: String, path: String) -> [String: Any] {
        let urlString = "file://" + path
        return [
            "tile-type": "file-tile",
            "tile-data": [
                "file-label": label,
                "bundle-identifier": bundleID,
                "file-data": ["_CFURLString": urlString],
            ],
        ]
    }

    private func spacerTile() -> [String: Any] {
        ["tile-type": "spacer-tile", "tile-data": [:]]
    }
}

import Foundation

enum DockReader {

    static func readApps() -> [DockApp] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: dockPlistPath())) else {
            return []
        }
        return parseApps(from: data)
    }

    /// Pure parser: turns a Dock plist payload into the resolved app list.
    /// Exposed for testing — does no I/O.
    static func parseApps(from plistData: Data) -> [DockApp] {
        guard let root = try? PropertyListSerialization.propertyList(
            from: plistData, options: [], format: nil
        ) as? [String: Any],
        let entries = root["persistent-apps"] as? [[String: Any]] else {
            return []
        }

        var apps: [DockApp] = []
        for entry in entries {
            guard let app = parse(entry: entry, indexInFilteredList: apps.count) else {
                continue
            }
            apps.append(app)
        }
        return apps
    }

    // MARK: - Private

    private static func dockPlistPath() -> String {
        let home = NSHomeDirectory()
            .components(separatedBy: "/Library/Containers").first
            ?? ("/Users/" + NSUserName())
        return home + "/Library/Preferences/com.apple.dock.plist"
    }

    private static func parse(entry: [String: Any], indexInFilteredList: Int) -> DockApp? {
        guard let tileType = entry["tile-type"] as? String,
              tileType == "file-tile",
              let tileData = entry["tile-data"] as? [String: Any] else { return nil }

        guard let bundleID = tileData["bundle-identifier"] as? String,
              !bundleID.isEmpty else { return nil }

        let name = tileData["file-label"] as? String ?? bundleID
        let appPath = extractAppPath(from: tileData) ?? ""

        return DockApp(
            name: name,
            bundleID: bundleID,
            appPath: appPath,
            shortcutLabel: DockApp.shortcutLabel(forIndex: indexInFilteredList)
        )
    }

    private static func extractAppPath(from tileData: [String: Any]) -> String? {
        guard let fileData = tileData["file-data"] as? [String: Any],
              let urlString = fileData["_CFURLString"] as? String else { return nil }

        if let url = URL(string: urlString), url.isFileURL {
            return url.path
        }
        if urlString.hasPrefix("file://") {
            let stripped = String(urlString.dropFirst("file://".count))
            return stripped.removingPercentEncoding ?? stripped
        }
        return nil
    }
}

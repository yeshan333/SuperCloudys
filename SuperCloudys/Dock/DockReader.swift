import Foundation

enum DockReader {

    static func readApps() -> (apps: [DockApp], error: String?) {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: dockPlistPath()))
            guard let entries = persistentApps(from: data) else {
                return ([], "Dock 配置格式无效。")
            }
            return (parseApps(entries), nil)
        } catch {
            return ([], "无法读取 Dock 配置：\(error.localizedDescription)")
        }
    }

    /// Pure parser: turns a Dock plist payload into the resolved app list.
    /// Exposed for testing — does no I/O.
    static func parseApps(from plistData: Data) -> [DockApp] {
        guard let entries = persistentApps(from: plistData) else { return [] }
        return parseApps(entries)
    }

    private static func parseApps(_ entries: [[String: Any]]) -> [DockApp] {
        var apps: [DockApp] = []
        for entry in entries {
            guard let app = parse(entry: entry, indexInFilteredList: apps.count) else {
                continue
            }
            apps.append(app)
        }
        return apps
    }

    private static func persistentApps(from data: Data) -> [[String: Any]]? {
        guard let root = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any] else { return nil }
        return root["persistent-apps"] as? [[String: Any]]
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

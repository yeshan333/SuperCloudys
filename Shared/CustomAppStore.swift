import Foundation

struct CustomApp: Codable, Identifiable, Equatable {
    var id: String { appPath }
    let name: String
    let appPath: String
}

enum CustomAppStore {

    // MARK: - Path (computed once)

    private static let configURL: URL = {
        let home = NSHomeDirectory()
            .components(separatedBy: "/Library/Containers").first
            ?? ("/Users/" + NSUserName())
        let base = URL(fileURLWithPath: home)
        let dir = base.appendingPathComponent("Library/Application Support/SuperCloudys")

        // Migrate from legacy "RMenu" directory if present
        let legacy = base.appendingPathComponent("Library/Application Support/RMenu")
        let fm = FileManager.default
        if fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: dir.path) {
            try? fm.moveItem(at: legacy, to: dir)
        }

        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("custom_apps.json")
    }()

    // MARK: - In-memory cache (per-process, mtime-invalidated)

    private static let cacheLock = NSLock()
    private static var cachedApps: [CustomApp]?
    private static var cachedMTime: Date?

    static func load() -> [CustomApp] {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        let currentMTime = fileMTime()

        // Cache hit when both the cached snapshot and the file mtime agree
        // (also handles "file missing on both sides" => return cached empty)
        if let cached = cachedApps, cachedMTime == currentMTime {
            return cached
        }

        let apps = decodeFromDisk()
        cachedApps = apps
        cachedMTime = currentMTime
        return apps
    }

    static func save(_ apps: [CustomApp]) {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        try? data.write(to: configURL, options: .atomic)

        cacheLock.lock()
        cachedApps = apps
        cachedMTime = fileMTime()
        cacheLock.unlock()
    }

    static func add(_ app: CustomApp) {
        var apps = load()
        guard !apps.contains(where: { $0.appPath == app.appPath }) else { return }
        apps.append(app)
        save(apps)
    }

    static func remove(at index: Int) {
        var apps = load()
        guard index >= 0, index < apps.count else { return }
        apps.remove(at: index)
        save(apps)
    }

    static func remove(_ app: CustomApp) {
        var apps = load()
        apps.removeAll { $0.appPath == app.appPath }
        save(apps)
    }

    /// 文件最后修改时间,供消费方做缓存失效判断
    static func fileMTime() -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: configURL.path)
        return attrs?[.modificationDate] as? Date
    }

    // MARK: - Private

    private static func decodeFromDisk() -> [CustomApp] {
        guard let data = try? Data(contentsOf: configURL),
              let apps = try? JSONDecoder().decode([CustomApp].self, from: data) else {
            return []
        }
        return apps
    }
}

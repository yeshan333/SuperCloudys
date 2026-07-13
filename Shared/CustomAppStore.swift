import Foundation
import os

struct CustomApp: Codable, Identifiable, Equatable {
    var id: String { appPath }
    let name: String
    let appPath: String
    let bundleID: String?

    init(name: String, appPath: String, bundleID: String? = nil) {
        self.name = name
        self.appPath = appPath
        self.bundleID = bundleID
    }
}

enum CustomAppStore {

    private static let log = Logger(subsystem: "com.yeshan333.SuperCloudys", category: "CustomApps")

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
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        let config = dir.appendingPathComponent("custom_apps.json")
        let legacyConfig = legacy.appendingPathComponent("custom_apps.json")
        if fm.fileExists(atPath: legacyConfig.path), !fm.fileExists(atPath: config.path) {
            try? fm.moveItem(at: legacyConfig, to: config)
        }
        if fm.fileExists(atPath: config.path) {
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
        }
        return config
    }()

    // MARK: - In-memory cache (per-process, mtime-invalidated)

    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var cachedApps: [CustomApp]?
    private nonisolated(unsafe) static var cachedMTime: Date?

    static func load() -> [CustomApp] {
        let currentMTime = fileMTime()

        cacheLock.lock()
        if let cached = cachedApps, cachedMTime == currentMTime {
            let result = cached
            cacheLock.unlock()
            return result
        }
        cacheLock.unlock()

        let apps = decodeFromDisk()
        
        cacheLock.lock()
        cachedApps = apps
        cachedMTime = currentMTime
        cacheLock.unlock()
        
        return apps
    }

    @discardableResult
    static func save(_ apps: [CustomApp]) -> Bool {
        do {
            try JSONEncoder().encode(apps).write(to: configURL, options: .atomic)
        } catch {
            log.error("Cannot save custom apps: \(error.localizedDescription, privacy: .public)")
            return false
        }
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: configURL.path
            )
        } catch {
            log.warning("Cannot restrict custom app config permissions: \(error.localizedDescription, privacy: .public)")
        }

        let mtime = fileMTime()
        cacheLock.lock()
        cachedApps = apps
        cachedMTime = mtime
        cacheLock.unlock()
        return true
    }

    @discardableResult
    static func add(_ app: CustomApp) -> Bool {
        var apps = load()
        guard !apps.contains(where: { existing in
            existing.appPath == app.appPath
                || (app.bundleID.map { $0 == existing.bundleID } ?? false)
        }) else { return true }
        apps.append(app)
        return save(apps)
    }

    static func remove(at index: Int) -> Bool {
        var apps = load()
        guard index >= 0, index < apps.count else { return false }
        apps.remove(at: index)
        return save(apps)
    }

    static func remove(_ app: CustomApp) -> Bool {
        var apps = load()
        apps.removeAll { $0.appPath == app.appPath }
        return save(apps)
    }

    /// 文件最后修改时间,供消费方做缓存失效判断
    static func fileMTime() -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: configURL.path)
        return attrs?[.modificationDate] as? Date
    }

    // MARK: - Private

    private static func decodeFromDisk() -> [CustomApp] {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch {
            log.error("Cannot read custom apps: \(error.localizedDescription, privacy: .public)")
            return []
        }
        do {
            return try JSONDecoder().decode([CustomApp].self, from: data)
        } catch {
            let backup = configURL.deletingPathExtension()
                .appendingPathExtension("corrupt-\(UUID().uuidString).json")
            do {
                try FileManager.default.moveItem(at: configURL, to: backup)
                log.error("Invalid custom app config moved to \(backup.path, privacy: .public)")
            } catch {
                log.error("Invalid custom app config could not be backed up: \(error.localizedDescription, privacy: .public)")
            }
            return []
        }
    }
}

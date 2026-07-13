import Foundation
import os

final class ClipboardStore: @unchecked Sendable {

    private let log = Logger(subsystem: "com.yeshan333.SuperCloudys", category: "ClipboardStore")
    private let storageURL: URL
    private let assetsDir: URL
    private var maxEntries: Int

    private var entries: [ClipboardEntry] = []
    private var storedError: String?
    private let lock = NSLock()
    private var saveWorkItem: DispatchWorkItem?
    private var saveGeneration = 0
    private var pendingAssetRemovals: [PendingAssetRemoval] = []
    private let saveQueue = DispatchQueue(label: "com.yeshan333.SuperCloudys.storeSave")

    private struct PendingAssetRemoval {
        let generation: Int
        let entry: ClipboardEntry
    }

    init(maxEntries: Int = 500, storageDirectory: URL? = nil) {
        let baseDir = storageDirectory ?? Self.defaultStorageDir()
        self.storageURL = baseDir.appendingPathComponent("clipboard_history.json")
        self.assetsDir = baseDir.appendingPathComponent("ClipboardAssets")
        self.maxEntries = max(1, maxEntries)

        do {
            try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        } catch {
            recordError("无法创建剪贴板存储：\(error.localizedDescription)")
        }
        setPermissions(0o700, at: baseDir)
        do {
            try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        } catch {
            recordError("无法创建剪贴板图片目录：\(error.localizedDescription)")
        }
        setPermissions(0o700, at: assetsDir)

        let loaded = loadFromDisk()
        self.entries = loaded.entries
        let removed = trimIfNeededLocked()
        var canReconcileAssets = loaded.canReconcileAssets
        if !removed.isEmpty {
            if write(entries) {
                removeAssets(for: removed)
            } else {
                canReconcileAssets = false
            }
        }
        if canReconcileAssets {
            removeOrphanedAssets()
        }
    }

    // MARK: - Public

    var allEntries: [ClipboardEntry] {
        withLock { entries }
    }

    var pinnedEntries: [ClipboardEntry] {
        withLock { entries.filter(\.isPinned) }
    }

    var assetsDirectory: URL { assetsDir }
    var lastError: String? { withLock { storedError } }

    func insert(_ entry: ClipboardEntry) {
        let removed: [ClipboardEntry] = withLock {
            if let index = entries.firstIndex(where: { $0.fingerprint == entry.fingerprint && !$0.isPinned }) {
                var existing = entries.remove(at: index)
                existing.lastUsedAt = Date()
                entries.insert(existing, at: 0)
                return [entry]
            }

            entries.insert(entry, at: 0)
            return trimIfNeededLocked()
        }
        scheduleSave(removing: removed)
    }

    func togglePin(id: UUID) {
        let changed = withLock {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
            entries[index].isPinned.toggle()
            return true
        }
        if changed { scheduleSave() }
    }

    func markUsed(id: UUID) {
        let changed = withLock {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
            entries[index].lastUsedAt = Date()
            return true
        }
        if changed { scheduleSave() }
    }

    func delete(id: UUID) {
        let removed = withLock { () -> [ClipboardEntry] in
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return [] }
            return [entries.remove(at: index)]
        }
        guard !removed.isEmpty else { return }
        scheduleSave(delay: 0, removing: removed)
    }

    func clearUnpinned() {
        let removed = withLock { removeEntries { !$0.isPinned } }
        guard !removed.isEmpty else { return }
        scheduleSave(delay: 0, removing: removed)
    }

    func clearAll() {
        let removed = withLock { removeEntries { _ in true } }
        guard !removed.isEmpty else { return }
        scheduleSave(delay: 0, removing: removed)
    }

    func search(query: String) -> [ClipboardEntry] {
        let snapshot = allEntries
        return snapshot.filter { entry in
            entry.title.range(of: query, options: .caseInsensitive) != nil
                || (entry.plainText?.range(of: query, options: .caseInsensitive) != nil)
                || (entry.sourceAppName?.range(of: query, options: .caseInsensitive) != nil)
        }
    }

    func filter(by type: ClipboardContentType) -> [ClipboardEntry] {
        withLock { entries.filter { $0.contentType == type } }
    }

    func updateMaxEntries(_ value: Int) {
        let removed = withLock {
            maxEntries = max(1, value)
            return trimIfNeededLocked()
        }
        guard !removed.isEmpty else { return }
        scheduleSave(delay: 0, removing: removed)
    }

    func applyRetention(maxAge: TimeInterval) {
        guard maxAge > 0 else { return }
        let cutoff = Date().addingTimeInterval(-maxAge)
        let removed = withLock {
            removeEntries { !$0.isPinned && ($0.lastUsedAt ?? $0.createdAt) < cutoff }
        }
        guard !removed.isEmpty else { return }
        scheduleSave(delay: 0, removing: removed)
    }

    func discardAssets(for entry: ClipboardEntry) {
        removeAssets(for: [entry])
    }

    func flush() {
        let (snapshot, generation) = withLock { () -> ([ClipboardEntry], Int) in
            saveWorkItem?.cancel()
            saveWorkItem = nil
            saveGeneration += 1
            return (entries, saveGeneration)
        }
        let saved = saveQueue.sync { write(snapshot) }
        if saved { removePersistedAssets(upTo: generation) }
    }

    // MARK: - Private

    private func trimIfNeededLocked() -> [ClipboardEntry] {
        var keptUnpinned = 0
        return removeEntries { entry in
            guard !entry.isPinned else { return false }
            defer { keptUnpinned += 1 }
            return keptUnpinned >= maxEntries
        }
    }

    private func removeEntries(where shouldRemove: (ClipboardEntry) -> Bool) -> [ClipboardEntry] {
        var removed: [ClipboardEntry] = []
        entries.removeAll { entry in
            let remove = shouldRemove(entry)
            if remove { removed.append(entry) }
            return remove
        }
        return removed
    }

    private func scheduleSave(
        delay: TimeInterval = 2,
        removing removed: [ClipboardEntry] = []
    ) {
        let item: DispatchWorkItem = withLock {
            saveWorkItem?.cancel()
            saveGeneration += 1
            let generation = saveGeneration
            let snapshot = entries
            pendingAssetRemovals.append(contentsOf: removed.map {
                PendingAssetRemoval(generation: generation, entry: $0)
            })
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.withLock({ self.saveGeneration == generation }) else { return }
                if self.write(snapshot) {
                    self.removePersistedAssets(upTo: generation)
                }
            }
            saveWorkItem = item
            return item
        }
        saveQueue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    @discardableResult
    private func write(_ snapshot: [ClipboardEntry]) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(to: storageURL, options: .atomic)
            setPermissions(0o600, at: storageURL)
            withLock { storedError = nil }
            return true
        } catch {
            recordError("无法保存剪贴板历史：\(error.localizedDescription)")
            return false
        }
    }

    private func loadFromDisk() -> (entries: [ClipboardEntry], canReconcileAssets: Bool) {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return ([], true) }
        guard let data = try? Data(contentsOf: storageURL) else {
            recordError("无法读取剪贴板历史。")
            return ([], false)
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return (try decoder.decode([ClipboardEntry].self, from: data), true)
        } catch {
            let backup = storageURL.deletingPathExtension()
                .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            do {
                try FileManager.default.moveItem(at: storageURL, to: backup)
                recordError("剪贴板历史损坏，已备份并重置。")
            } catch {
                recordError("剪贴板历史损坏且无法备份：\(error.localizedDescription)")
            }
            return ([], false)
        }
    }

    private func removeOrphanedAssets() {
        let referenced = Set(entries.flatMap {
            [$0.imagePath, $0.thumbnailPath].compactMap { $0 }
        }.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: assetsDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let orphaned = files.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                && !referenced.contains(url.standardizedFileURL.path)
        }
        removeAssetPaths(Set(orphaned.map(\.path)))
    }

    private func removeAssets(for removed: [ClipboardEntry]) {
        let paths = Set(removed.flatMap { [$0.imagePath, $0.thumbnailPath].compactMap { $0 } })
        removeAssetPaths(paths)
    }

    private func removePersistedAssets(upTo generation: Int) {
        let paths: Set<String> = withLock {
            var ready: [ClipboardEntry] = []
            pendingAssetRemovals.removeAll { removal in
                guard removal.generation <= generation else { return false }
                ready.append(removal.entry)
                return true
            }
            let referenced = Set(entries.flatMap {
                [$0.imagePath, $0.thumbnailPath].compactMap { $0 }
            })
            let candidates = Set(ready.flatMap {
                [$0.imagePath, $0.thumbnailPath].compactMap { $0 }
            })
            return candidates.subtracting(referenced)
        }
        removeAssetPaths(paths)
    }

    private func removeAssetPaths(_ paths: Set<String>) {
        let root = assetsDir.standardizedFileURL.path + "/"
        for path in paths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard url.path.hasPrefix(root) else {
                log.warning("Refusing to delete clipboard asset outside storage: \(url.path, privacy: .public)")
                continue
            }
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                log.error("Cannot delete clipboard asset: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func recordError(_ message: String) {
        withLock { storedError = message }
        log.error("\(message, privacy: .public)")
    }

    private func setPermissions(_ permissions: Int, at url: URL) {
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: permissions],
                ofItemAtPath: url.path
            )
        } catch {
            log.warning("Cannot restrict permissions for \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func defaultStorageDir() -> URL {
        let home = NSHomeDirectory()
            .components(separatedBy: "/Library/Containers").first
            ?? ("/Users/" + NSUserName())
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/SuperCloudys")
    }
}

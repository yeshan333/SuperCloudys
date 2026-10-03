import Foundation
import os

final class ClipboardStore: @unchecked Sendable {

    private let log = Logger(subsystem: "com.yeshan333.SuperCloudys", category: "ClipboardStore")
    private let storageURL: URL
    private let assetsDir: URL
    private var maxEntries: Int

    private var entries: [ClipboardEntry] = []
    private var storedError: String?
    private var persistenceBlocked = false
    private let lock = NSLock()
    private var saveWorkItem: DispatchWorkItem?
    private var saveGeneration = 0
    private var pendingAssetRemovals: [PendingAssetRemoval] = []
    private let saveQueue = DispatchQueue(label: "com.yeshan333.SuperCloudys.storeSave")

    private struct PendingAssetRemoval {
        let generation: Int
        let entry: ClipboardEntry
    }

    init(maxEntries: Int = 3000, storageDirectory: URL? = nil) {
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

        let legacyAssetsProtected = preserveLegacyRecoveryAssets()
        let loaded = loadFromDisk()
        self.entries = loaded.entries
        let removed = trimIfNeededLocked()
        var canReconcileAssets = loaded.canReconcileAssets && legacyAssetsProtected
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
            if let index = entries.firstIndex(where: { $0.fingerprint == entry.fingerprint && !$0.isPinned && $0.hasSameContent(as: entry) }) {
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
        ClipboardSearch.filter(allEntries, query: query) ?? []
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
        guard !persistenceBlocked else { return false }
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
            persistenceBlocked = true
            recordError("无法读取剪贴板历史，已暂停保存以保护原文件。")
            return ([], false)
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return (try decoder.decode([ClipboardEntry].self, from: data), true)
        } catch {
            do {
                let backup = try preserveCorruptHistory([storageURL])
                recordError("剪贴板历史损坏，历史和图片已备份至 \(backup.lastPathComponent)。")
            } catch {
                persistenceBlocked = true
                recordError("剪贴板历史损坏且无法完整备份，已暂停保存：\(error.localizedDescription)")
            }
            return ([], false)
        }
    }

    private func preserveLegacyRecoveryAssets() -> Bool {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: storageURL.deletingLastPathComponent(), includingPropertiesForKeys: nil
            )
            let legacy = files.filter {
                $0.lastPathComponent.hasPrefix("clipboard_history.corrupt-")
                    && $0.pathExtension == "json"
            }
            guard !legacy.isEmpty else { return true }
            _ = try preserveCorruptHistory(legacy)
            // All old backups and potentially associated images are now together.
            for file in legacy { try FileManager.default.removeItem(at: file) }
            return true
        } catch {
            persistenceBlocked = true
            recordError("无法保护旧版损坏历史备份，已暂停保存和清理：\(error.localizedDescription)")
            return false
        }
    }

    private func preserveCorruptHistory(_ histories: [URL]) throws -> URL {
        let manager = FileManager.default
        let backup = storageURL.deletingLastPathComponent()
            .appendingPathComponent("clipboard_recovery_" + UUID().uuidString)
        try manager.createDirectory(at: backup, withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])
        // Keep originals intact until every recovery file is safely copied. A failed
        // backup disables writes and cleanup for this instance; a later launch can retry.
        for history in histories {
            let historyBackup = backup.appendingPathComponent(history.lastPathComponent)
            try manager.copyItem(at: history, to: historyBackup)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyBackup.path)
        }
        let assetBackup = backup.appendingPathComponent(assetsDir.lastPathComponent)
        try manager.copyItem(at: assetsDir, to: assetBackup)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: assetBackup.path)
        if let files = manager.enumerator(at: assetBackup,
                                          includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            for case let file as URL in files {
                let values = try file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { continue }
                try manager.setAttributes([.posixPermissions: values.isDirectory == true ? 0o700 : 0o600],
                                          ofItemAtPath: file.path)
            }
        }
        return backup
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

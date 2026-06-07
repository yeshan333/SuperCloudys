import Foundation

final class ClipboardStore {

    private let storageURL: URL
    private let assetsDir: URL
    private let maxEntries: Int

    private var entries: [ClipboardEntry] = []
    private let lock = NSLock()
    private var saveWorkItem: DispatchWorkItem?
    private let saveQueue = DispatchQueue(label: "com.yeshan333.SuperCloudys.storeSave")

    init(maxEntries: Int = 500, storageDirectory: URL? = nil) {
        let baseDir = storageDirectory ?? Self.defaultStorageDir()
        try? FileManager.default.createDirectory(
            at: baseDir, withIntermediateDirectories: true
        )
        self.storageURL = baseDir.appendingPathComponent("clipboard_history.json")
        self.assetsDir = baseDir.appendingPathComponent("ClipboardAssets")
        try? FileManager.default.createDirectory(
            at: assetsDir, withIntermediateDirectories: true
        )
        self.maxEntries = maxEntries
        self.entries = loadFromDisk()
    }

    // MARK: - Public

    var allEntries: [ClipboardEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    var pinnedEntries: [ClipboardEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter(\.isPinned)
    }

    func insert(_ entry: ClipboardEntry) {
        lock.lock()
        defer { lock.unlock() }

        if let idx = entries.firstIndex(where: { $0.fingerprint == entry.fingerprint && !$0.isPinned }) {
            var existing = entries[idx]
            existing.lastUsedAt = Date()
            entries.remove(at: idx)
            entries.insert(existing, at: 0)
        } else {
            entries.insert(entry, at: 0)
            trimIfNeeded()
        }
        scheduleSave()
    }

    func togglePin(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].isPinned.toggle()
        scheduleSave()
    }

    func delete(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll { $0.id == id }
        scheduleSave()
    }

    func clearUnpinned() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll { !$0.isPinned }
        flushSave()
    }

    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        flushSave()
    }

    func search(query: String) -> [ClipboardEntry] {
        lock.lock()
        defer { lock.unlock() }
        let q = query.lowercased()
        return entries.filter { entry in
            entry.title.lowercased().contains(q)
                || (entry.plainText?.lowercased().contains(q) ?? false)
                || (entry.sourceAppName?.lowercased().contains(q) ?? false)
        }
    }

    func filter(by type: ClipboardContentType) -> [ClipboardEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter { $0.contentType == type }
    }

    var assetsDirectory: URL { assetsDir }

    func flush() {
        saveWorkItem?.cancel()
        lock.lock()
        let snapshot = entries
        lock.unlock()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    // MARK: - Retention

    func applyRetention(maxAge: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        let cutoff = Date().addingTimeInterval(-maxAge)
        entries.removeAll { !$0.isPinned && $0.createdAt < cutoff }
        flushSave()
    }

    // MARK: - Private

    private func trimIfNeeded() {
        let pinned = entries.filter(\.isPinned)
        let unpinned = entries.filter { !$0.isPinned }
        guard unpinned.count > maxEntries else { return }
        entries = pinned + Array(unpinned.prefix(maxEntries))
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let snapshot = entries
        let url = storageURL
        let item = DispatchWorkItem {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
        saveWorkItem = item
        saveQueue.asyncAfter(deadline: .now() + 2.0, execute: item)
    }

    private func flushSave() {
        saveWorkItem?.cancel()
        let snapshot = entries
        let url = storageURL
        saveQueue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func loadFromDisk() -> [ClipboardEntry] {
        guard let data = try? Data(contentsOf: storageURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([ClipboardEntry].self, from: data) else { return [] }
        return decoded
    }

    private static func defaultStorageDir() -> URL {
        let home = NSHomeDirectory()
            .components(separatedBy: "/Library/Containers").first
            ?? ("/Users/" + NSUserName())
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/SuperCloudys")
    }
}

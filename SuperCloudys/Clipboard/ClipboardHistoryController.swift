import AppKit
import os

@MainActor
final class ClipboardHistoryController: ObservableObject {

    static let shared = ClipboardHistoryController()

    enum PasteResult: Equatable {
        case pasted
        case cancelled
        case failed
    }

    typealias SearchFilter = @Sendable ([ClipboardEntry], String, ClipboardContentType?) -> [ClipboardEntry]?

    @Published private(set) var entries: [ClipboardEntry] = []
    @Published var searchQuery: String = "" {
        didSet {
            guard searchQuery != oldValue else { return }
            scheduleFilter(delay: searchQuery.isEmpty ? 0 : 0.15)
        }
    }
    @Published var typeFilter: ClipboardContentType? {
        didSet {
            guard typeFilter != oldValue else { return }
            scheduleFilter(delay: 0)
        }
    }
    @Published private(set) var filteredEntries: [ClipboardEntry] = []
    @Published var isPanelVisible: Bool = false {
        didSet {
            guard isPanelVisible != oldValue else { return }
            if isPanelVisible {
                pasteGeneration &+= 1
                if needsFilter { scheduleFilter(delay: 0) }
            } else {
                cancelFilter()
            }
        }
    }
    @Published private(set) var isMonitoringPaused: Bool
    @Published private(set) var retentionDays: Int
    @Published private(set) var maxEntries: Int
    @Published private(set) var excludedApps: [String]
    @Published private(set) var previousApp: NSRunningApplication?
    var storageError: String? { store.lastError }

    private let store: ClipboardStore
    private let monitor: ClipboardMonitorService
    private let settings: ClipboardSettings
    private let log = Logger(subsystem: "com.yeshan333.SuperCloudys", category: "ClipboardHistory")
    private var filterTask: Task<Void, Never>?
    private var filterWorker: Task<FilterResult?, Never>?
    private var sortedEntries: [ClipboardEntry]?
    private var needsFilter = true
    private var pasteGeneration: UInt64 = 0
    private let searchFilter: SearchFilter

    private struct FilterResult: Sendable {
        let sortedEntries: [ClipboardEntry]
        let matches: [ClipboardEntry]
    }

    private init() {
        let settings = ClipboardSettings.shared
        let store = ClipboardStore(maxEntries: settings.maxEntries)
        if settings.retentionDays > 0 {
            store.applyRetention(maxAge: TimeInterval(settings.retentionDays) * 86_400)
        }
        self.searchFilter = { @Sendable entries, query, type in
            Self.runSearch(entries, query: query, type: type)
        }
        self.settings = settings
        self.store = store
        self.monitor = ClipboardMonitorService(settings: settings)
        self.isMonitoringPaused = settings.isPaused
        self.retentionDays = settings.retentionDays
        self.maxEntries = settings.maxEntries
        self.excludedApps = settings.excludedApps.sorted()
        let frontmost = NSWorkspace.shared.frontmostApplication
        self.previousApp = frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier
            ? nil
            : frontmost
        self.monitor.assetsDirectory = store.assetsDirectory
        self.entries = store.allEntries
        monitor.delegate = self
        scheduleFilter(delay: 0)
    }

    // For testing
    init(
        store: ClipboardStore,
        monitor: ClipboardMonitorService,
        settings: ClipboardSettings,
        searchFilter: @escaping SearchFilter = { @Sendable entries, query, type in
            ClipboardHistoryController.runSearch(entries, query: query, type: type)
        }
    ) {
        self.searchFilter = searchFilter
        self.store = store
        self.monitor = monitor
        self.settings = settings
        self.isMonitoringPaused = settings.isPaused
        self.retentionDays = settings.retentionDays
        self.maxEntries = settings.maxEntries
        self.excludedApps = settings.excludedApps.sorted()
        self.previousApp = nil
        self.entries = store.allEntries
        monitor.delegate = self
        scheduleFilter(delay: 0)
    }

    func startMonitoring() {
        guard !isMonitoringPaused else { return }
        monitor.start()
        log.info("Clipboard history monitoring started")
    }

    func stopMonitoring() {
        monitor.stop()
    }

    func togglePin(id: UUID) {
        store.togglePin(id: id)
        reloadEntries()
    }

    func delete(id: UUID) {
        store.delete(id: id)
        reloadEntries()
    }

    func clearUnpinned() {
        store.clearUnpinned()
        reloadEntries()
    }

    func clearAll() {
        store.clearAll()
        reloadEntries()
    }

    func setMonitoringPaused(_ paused: Bool) {
        settings.isPaused = paused
        isMonitoringPaused = paused
        if paused {
            monitor.stop()
        } else {
            monitor.start()
        }
    }

    func setRetentionDays(_ days: Int) {
        let days = max(0, days)
        settings.retentionDays = days
        retentionDays = days
        if days > 0 {
            store.applyRetention(maxAge: TimeInterval(days) * 86_400)
            reloadEntries()
        }
    }

    func setMaxEntries(_ count: Int) {
        let count = max(1, count)
        settings.maxEntries = count
        maxEntries = count
        store.updateMaxEntries(count)
        reloadEntries()
    }

    func addExcludedApp(bundleID: String) {
        var apps = settings.excludedApps
        apps.insert(bundleID)
        settings.excludedApps = apps
        excludedApps = apps.sorted()
    }

    func removeExcludedApp(bundleID: String) {
        var apps = settings.excludedApps
        apps.remove(bundleID)
        settings.excludedApps = apps
        excludedApps = apps.sorted()
    }

    func flush() {
        store.flush()
    }

    func clearSearch() {
        guard !searchQuery.isEmpty else { return }
        searchQuery = ""
    }

    func cycleTypeFilter(reverse: Bool = false) {
        let filters = [nil] + ClipboardContentType.filterCases.map(Optional.some)
        guard let currentIndex = filters.firstIndex(where: { $0 == typeFilter }) else {
            typeFilter = nil
            return
        }
        let nextIndex = reverse
            ? (currentIndex == filters.startIndex ? filters.endIndex - 1 : currentIndex - 1)
            : (currentIndex + 1) % filters.count
        typeFilter = filters[nextIndex]
    }

    @discardableResult
    func copyToClipboard(
        _ entry: ClipboardEntry,
        isCurrent: @escaping @MainActor () -> Bool = { true }
    ) async -> Bool {
        let pasteboard = NSPasteboard.general
        let writer: () -> Bool

        switch entry.contentType {
        case .fileGroup:
            guard let paths = entry.filePaths, !paths.isEmpty else { return false }
            let urls = paths.map { URL(fileURLWithPath: $0) as NSURL }
            writer = { pasteboard.writeObjects(urls) }
        case .color:
            let value = entry.colorHex ?? entry.title
            writer = { pasteboard.setString(value, forType: .string) }
        case .image:
            guard let path = entry.imagePath else { return false }
            let url = URL(fileURLWithPath: path)
            guard let data = await Task.detached(priority: .userInitiated, operation: {
                try? Data(contentsOf: url, options: .mappedIfSafe)
            }).value,
                  !data.isEmpty else { return false }
            let type: NSPasteboard.PasteboardType = url.pathExtension.lowercased() == "tiff"
                ? .tiff
                : .png
            writer = { pasteboard.setData(data, forType: type) }
        default:
            guard let text = entry.plainText else { return false }
            writer = { pasteboard.setString(text, forType: .string) }
        }
        // 图片读取可能跨越一次面板重开；过期操作不能再覆盖剪贴板。
        guard isCurrent(), !Task.isCancelled else { return false }
        let copied = monitor.performSelfWrite {
            pasteboard.clearContents()
            return writer()
        }
        if copied {
            store.markUsed(id: entry.id)
            reloadEntries()
        }
        return copied
    }

    @discardableResult
    func copyImagePathToClipboard(
        _ entry: ClipboardEntry,
        pasteboard: NSPasteboard = .general
    ) -> Bool {
        guard entry.contentType == .image,
              let path = entry.imagePath, !path.isEmpty else { return false }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return false }

        let copied = monitor.performSelfWrite {
            pasteboard.clearContents()
            return pasteboard.setString(path, forType: .string)
        }
        if copied {
            store.markUsed(id: entry.id)
            reloadEntries()
        }
        return copied
    }

    func pasteToFrontApp(_ entry: ClipboardEntry) async -> PasteResult {
        // 在首次挂起前固定目标，避免图片读取期间重开面板改变粘贴目的地。
        guard canPasteToPreviousApp, let app = previousApp else { return .failed }
        return await performPaste(
            copy: { isCurrent in
                await self.copyToClipboard(entry, isCurrent: isCurrent)
            },
            paste: { isCurrent in
                guard isCurrent(), !app.isTerminated else { return false }
                app.activate(options: [.activateAllWindows])
                for _ in 0..<20 {
                    guard isCurrent(), !app.isTerminated else { return false }
                    if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                        return Self.simulatePaste()
                    }
                    _ = AccessibilityActivator.activate(pid: app.processIdentifier)
                    do {
                        try await Task.sleep(nanoseconds: 50_000_000)
                    } catch {
                        return false
                    }
                }
                self.log.warning("Paste cancelled because target app did not become frontmost")
                return false
            }
        )
    }

    // Separates session validity from platform effects so cancellation is testable without
    // writing the system clipboard or sending keyboard events to another application.
    func performPaste(
        copy: @MainActor (@escaping @MainActor () -> Bool) async -> Bool,
        paste: @MainActor (@escaping @MainActor () -> Bool) async -> Bool
    ) async -> PasteResult {
        pasteGeneration &+= 1
        let generation = pasteGeneration
        let isCurrent: @MainActor () -> Bool = { [weak self] in
            !Task.isCancelled && self?.pasteGeneration == generation
        }
        guard isCurrent() else { return .cancelled }
        let copied = await copy(isCurrent)
        guard isCurrent() else { return .cancelled }
        guard copied else { return .failed }
        let pasted = await paste(isCurrent)
        guard isCurrent() else { return .cancelled }
        return pasted ? .pasted : .failed
    }

    var canPasteToPreviousApp: Bool {
        AccessibilityActivator.isTrusted && previousApp?.isTerminated == false
    }

    func rememberFrontmostApp() {
        pasteGeneration &+= 1
        let app = NSWorkspace.shared.frontmostApplication
        if app?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = app
        }
    }

    // MARK: - Private

    private func reloadEntries() {
        entries = store.allEntries
        sortedEntries = nil
        scheduleFilter(delay: 0)
    }

    private func cancelFilter() {
        filterTask?.cancel()
        filterWorker?.cancel()
        filterTask = nil
        filterWorker = nil
    }

    private func scheduleFilter(delay: TimeInterval = 0.15) {
        cancelFilter()
        needsFilter = true
        // 常驻记录时不执行全文搜索，打开面板后再处理最新快照。
        guard isPanelVisible else {
            filteredEntries = []
            return
        }
        let snapshot = entries
        let cachedOrder = sortedEntries
        let query = searchQuery
        let filter = typeFilter
        let searchFilter = self.searchFilter
        filterTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled, let self else { return }
            let worker = Task.detached(priority: .userInitiated) { () -> FilterResult? in
                guard !Task.isCancelled else { return nil }
                let sorted = cachedOrder ?? ClipboardSearch.sorted(snapshot)
                guard let matches = searchFilter(sorted, query, filter) else { return nil }
                return FilterResult(sortedEntries: sorted, matches: matches)
            }
            self.filterWorker = worker
            guard let result = await worker.value, !Task.isCancelled else { return }
            self.sortedEntries = result.sortedEntries
            self.filteredEntries = result.matches
            self.needsFilter = false
            self.filterWorker = nil
            self.filterTask = nil
        }
    }

    nonisolated static func runSearch(
        _ entries: [ClipboardEntry], query: String, type: ClipboardContentType?
    ) -> [ClipboardEntry]? {
        ClipboardSearch.filter(entries, query: query, type: type, isCancelled: { Task.isCancelled })
    }

    private static func simulatePaste() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        guard let keyDown = CGEvent(
            keyboardEventSource: source, virtualKey: 0x09, keyDown: true
        ), let keyUp = CGEvent(
            keyboardEventSource: source, virtualKey: 0x09, keyDown: false
        ) else { return false }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}

extension ClipboardHistoryController: ClipboardMonitorDelegate {
    nonisolated func clipboardMonitor(
        _ monitor: ClipboardMonitorService,
        didCapture entry: ClipboardEntry,
        generation: Int
    ) {
        Task { @MainActor in
            guard !self.isMonitoringPaused, self.monitor.isCaptureValid(generation) else {
                self.store.discardAssets(for: entry)
                return
            }
            self.store.insert(entry)
            if self.retentionDays > 0 {
                self.store.applyRetention(maxAge: TimeInterval(self.retentionDays) * 86_400)
            }
            self.reloadEntries()
        }
    }
}

import AppKit
import os

@MainActor
final class ClipboardHistoryController: ObservableObject {

    static let shared = ClipboardHistoryController()

    @Published private(set) var entries: [ClipboardEntry] = []
    @Published var searchQuery: String = "" { didSet { scheduleFilter() } }
    @Published var typeFilter: ClipboardContentType? { didSet { scheduleFilter(delay: 0) } }
    @Published private(set) var filteredEntries: [ClipboardEntry] = []
    @Published var isPanelVisible: Bool = false
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

    private init() {
        let settings = ClipboardSettings.shared
        let store = ClipboardStore(maxEntries: settings.maxEntries)
        if settings.retentionDays > 0 {
            store.applyRetention(maxAge: TimeInterval(settings.retentionDays) * 86_400)
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
        self.filteredEntries = entries
        monitor.delegate = self
        scheduleFilter(delay: 0)
    }

    // For testing
    init(store: ClipboardStore, monitor: ClipboardMonitorService, settings: ClipboardSettings) {
        self.store = store
        self.monitor = monitor
        self.settings = settings
        self.isMonitoringPaused = settings.isPaused
        self.retentionDays = settings.retentionDays
        self.maxEntries = settings.maxEntries
        self.excludedApps = settings.excludedApps.sorted()
        self.previousApp = nil
        self.entries = store.allEntries
        self.filteredEntries = entries
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
        scheduleFilter(delay: 0)
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
    func copyToClipboard(_ entry: ClipboardEntry) async -> Bool {
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

    func pasteToFrontApp(_ entry: ClipboardEntry) async -> Bool {
        guard canPasteToPreviousApp, await copyToClipboard(entry),
              let app = previousApp else { return false }
        app.activate(options: [.activateAllWindows])
        for _ in 0..<20 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                return Self.simulatePaste()
            }
            _ = AccessibilityActivator.activate(pid: app.processIdentifier)
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        log.warning("Paste cancelled because target app did not become frontmost")
        return false
    }

    var canPasteToPreviousApp: Bool {
        AccessibilityActivator.isTrusted && previousApp?.isTerminated == false
    }

    func rememberFrontmostApp() {
        let app = NSWorkspace.shared.frontmostApplication
        if app?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = app
        }
    }

    // MARK: - Private

    private func reloadEntries() {
        entries = store.allEntries
        scheduleFilter(delay: 0)
    }

    private func scheduleFilter(delay: TimeInterval = 0.15) {
        filterTask?.cancel()
        let snapshot = entries
        let query = searchQuery
        let filter = typeFilter
        filterTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) {
                Self.filterEntries(snapshot, query: query, type: filter)
            }.value
            guard !Task.isCancelled else { return }
            guard let self,
                  self.searchQuery == query,
                  self.typeFilter == filter else { return }
            self.filteredEntries = result
        }
    }

    nonisolated private static func filterEntries(
        _ entries: [ClipboardEntry],
        query: String,
        type: ClipboardContentType?
    ) -> [ClipboardEntry] {
        var result = entries
        if let type {
            result = result.filter {
                type == .text
                    ? $0.contentType == .text || $0.contentType == .richText
                    : $0.contentType == type
            }
        }
        if !query.isEmpty {
            result = result.filter { entry in
                entry.title.range(of: query, options: .caseInsensitive) != nil
                    || (entry.plainText?.range(of: query, options: .caseInsensitive) != nil)
                    || (entry.sourceAppName?.range(of: query, options: .caseInsensitive) != nil)
            }
        }

        result.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            let lhsDate = lhs.lastUsedAt ?? lhs.createdAt
            let rhsDate = rhs.lastUsedAt ?? rhs.createdAt
            return lhsDate > rhsDate
        }
        return result
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

import AppKit
import os

@MainActor
final class ClipboardHistoryController: ObservableObject {

    static let shared = ClipboardHistoryController()

    @Published private(set) var entries: [ClipboardEntry] = []
    @Published var searchQuery: String = "" { didSet { scheduleFilter() } }
    @Published var typeFilter: ClipboardContentType? { didSet { refreshFiltered() } }
    @Published private(set) var filteredEntries: [ClipboardEntry] = []
    @Published var isPanelVisible: Bool = false

    private let store: ClipboardStore
    private let monitor: ClipboardMonitorService
    private let settings: ClipboardSettings
    private let log = Logger(subsystem: "com.yeshan333.SuperCloudys", category: "ClipboardHistory")
    private var filterTask: DispatchWorkItem?

    var previousApp: NSRunningApplication?

    private init() {
        self.settings = .shared
        self.store = ClipboardStore(maxEntries: settings.maxEntries)
        self.monitor = ClipboardMonitorService(settings: settings)
        self.monitor.assetsDirectory = store.assetsDirectory
        self.entries = store.allEntries
        self.filteredEntries = entries
        monitor.delegate = self
    }

    // For testing
    init(store: ClipboardStore, monitor: ClipboardMonitorService, settings: ClipboardSettings) {
        self.store = store
        self.monitor = monitor
        self.settings = settings
        self.entries = store.allEntries
        self.filteredEntries = entries
        monitor.delegate = self
    }

    func startMonitoring() {
        guard !settings.isPaused else { return }
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

    func clearSearch() {
        guard !searchQuery.isEmpty else { return }
        searchQuery = ""
        filterTask?.cancel()
        filterTask = nil
        refreshFiltered()
    }

    func cycleTypeFilter(reverse: Bool = false) {
        let filters = [nil] + ClipboardContentType.allCases.map(Optional.some)
        guard let currentIndex = filters.firstIndex(where: { $0 == typeFilter }) else {
            typeFilter = nil
            return
        }
        let nextIndex = reverse
            ? (currentIndex == filters.startIndex ? filters.endIndex - 1 : currentIndex - 1)
            : (currentIndex + 1) % filters.count
        typeFilter = filters[nextIndex]
    }

    func copyToClipboard(_ entry: ClipboardEntry) {
        monitor.markSelfWrite()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch entry.contentType {
        case .fileGroup:
            if let paths = entry.filePaths {
                let urls = paths.map { URL(fileURLWithPath: $0) as NSURL }
                pasteboard.writeObjects(urls)
            }
        case .color:
            pasteboard.setString(entry.colorHex ?? entry.title, forType: .string)
        case .image:
            if let path = entry.imagePath, let image = NSImage(contentsOfFile: path) {
                pasteboard.writeObjects([image])
            }
        default:
            if let text = entry.plainText {
                pasteboard.setString(text, forType: .string)
            }
        }
    }

    func pasteToFrontApp(_ entry: ClipboardEntry) {
        copyToClipboard(entry)
        guard let app = previousApp else { return }
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            Self.simulatePaste()
        }
    }

    func rememberFrontmostApp() {
        previousApp = NSWorkspace.shared.frontmostApplication
    }

    // MARK: - Private

    private func reloadEntries() {
        entries = store.allEntries
        refreshFiltered()
    }

    private func scheduleFilter() {
        filterTask?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.refreshFiltered()
        }
        filterTask = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    private func refreshFiltered() {
        var result = entries
        if let type = typeFilter {
            result = result.filter { $0.contentType == type }
        }
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            result = result.filter { entry in
                entry.title.lowercased().contains(q)
                    || (entry.plainText?.lowercased().contains(q) ?? false)
                    || (entry.sourceAppName?.lowercased().contains(q) ?? false)
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
        
        filteredEntries = result
    }

    private static func simulatePaste() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

extension ClipboardHistoryController: ClipboardMonitorDelegate {
    nonisolated func clipboardMonitor(_ monitor: ClipboardMonitorService, didCapture entry: ClipboardEntry) {
        Task { @MainActor in
            self.store.insert(entry)
            self.reloadEntries()
        }
    }
}

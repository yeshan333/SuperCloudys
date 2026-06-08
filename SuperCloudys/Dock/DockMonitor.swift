import Foundation
import Combine

/// Reads Dock apps, observes changes to the Dock plist without polling, 
/// and keeps the global shortcut bindings in sync with the current Dock layout.
@MainActor
final class DockMonitor: ObservableObject {

    @Published private(set) var apps: [DockApp] = []
    @Published var shortcutsEnabled: Bool {
        didSet {
            DockShortcutSettings.shortcutsEnabled = shortcutsEnabled
            updateShortcuts()
        }
    }

    private var source: DispatchSourceFileSystemObject?
    private var lastBundleIDs: [String] = []

    init() {
        self.shortcutsEnabled = DockShortcutSettings.shortcutsEnabled
        refresh(forceRegister: true)
        startMonitoring()
    }

    deinit {
        source?.cancel()
    }

    /// Force a re-read of the Dock plist and re-register shortcuts.
    func refresh(forceRegister: Bool = false) {
        let newApps = DockReader.readApps()
        let newIDs = newApps.map(\.bundleID)
        let changed = newIDs != lastBundleIDs
        lastBundleIDs = newIDs
        self.apps = newApps
        if changed || forceRegister {
            updateShortcuts()
        }
    }

    private func updateShortcuts() {
        if shortcutsEnabled {
            DockShortcutManager.shared.register(apps: apps)
        } else {
            DockShortcutManager.shared.unregisterAll()
        }
    }

    private func startMonitoring() {
        let dockPlist = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Preferences/com.apple.dock.plist")
        monitorFile(at: dockPlist)
    }

    private func monitorFile(at url: URL) {
        source?.cancel()
        
        let fd = open(url.path, O_EVTONLY)
        guard fd != -1 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.monitorFile(at: url)
            }
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: DispatchQueue.main)
        src.setEventHandler { [weak self] in
            self?.refresh()
            let data = src.data
            if data.contains(.delete) || data.contains(.rename) {
                self?.monitorFile(at: url)
            }
        }
        src.setCancelHandler {
            close(fd)
        }
        src.resume()
        self.source = src
    }
}

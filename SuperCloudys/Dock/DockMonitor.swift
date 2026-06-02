import Foundation
import Combine

/// Reads Dock apps, polls for changes every 5 seconds, and keeps the
/// global shortcut bindings in sync with the current Dock layout.
@MainActor
final class DockMonitor: ObservableObject {

    @Published private(set) var apps: [DockApp] = []
    @Published var shortcutsEnabled: Bool {
        didSet {
            DockShortcutSettings.shortcutsEnabled = shortcutsEnabled
            updateShortcuts()
        }
    }

    private let pollInterval: Duration = .seconds(5)
    private var pollTask: Task<Void, Never>?
    private var lastBundleIDs: [String] = []

    init() {
        self.shortcutsEnabled = DockShortcutSettings.shortcutsEnabled
        // Prompt once for Accessibility so AXUIElement-based activation works.
        AccessibilityActivator.requestTrust()
        refresh(forceRegister: true)
        startPolling()
    }

    deinit {
        // Task.cancel() is thread-safe, safe to call from non-isolated deinit.
        pollTask?.cancel()
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

    private func startPolling() {
        pollTask = Task { [weak self, pollInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pollInterval)
                if Task.isCancelled { return }
                await self?.refresh()
            }
        }
    }
}

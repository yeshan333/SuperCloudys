import AppKit

enum DockAppLauncher {

    /// Toggle: if the app is frontmost, hide it; otherwise launch/activate it.
    static func toggle(bundleID: String) {
        if isFrontmost(bundleID: bundleID) {
            hide(bundleID: bundleID)
        } else {
            launchOrFocus(bundleID: bundleID)
        }
    }

    // MARK: - Private

    private static func isFrontmost(bundleID: String) -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    private static func launchOrFocus(bundleID: String) {
        if let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleID
        ).first {
            if running.isHidden { running.unhide() }
            // AX bypasses macOS 14+ focus-stealing when granted; falls back otherwise.
            if AccessibilityActivator.activate(pid: running.processIdentifier) {
                return
            }
            if #available(macOS 14.0, *) {
                running.activate()
            } else {
                running.activate(options: [.activateAllWindows])
            }
            return
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleID
        ) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(
            at: appURL, configuration: config, completionHandler: nil
        )
    }

    private static func hide(bundleID: String) {
        guard let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleID
        ).first else { return }
        running.hide()
    }
}

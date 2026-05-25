import AppKit
import os

enum DockAppLauncher {

    private static let log = Logger(subsystem: "com.yeshan333.RMenu", category: "DockLauncher")

    /// Toggle: if the app is frontmost, hide it; otherwise launch/activate it.
    /// `appPath` (from the Dock plist) is preferred over LaunchServices lookup,
    /// which can silently return nil under App Sandbox.
    static func toggle(bundleID: String, appPath: String = "") {
        if isFrontmost(bundleID: bundleID) {
            hide(bundleID: bundleID)
        } else {
            launchOrFocus(bundleID: bundleID, appPath: appPath)
        }
    }

    // MARK: - Private

    private static func isFrontmost(bundleID: String) -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    private static func launchOrFocus(bundleID: String, appPath: String) {
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

        guard let appURL = resolveAppURL(bundleID: bundleID, appPath: appPath) else {
            log.warning("Cannot launch \(bundleID, privacy: .public): no URL (path=\(appPath, privacy: .public))")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
            if let error {
                log.error("openApplication failed for \(bundleID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func resolveAppURL(bundleID: String, appPath: String) -> URL? {
        if !appPath.isEmpty, FileManager.default.fileExists(atPath: appPath) {
            return URL(fileURLWithPath: appPath)
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private static func hide(bundleID: String) {
        guard let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleID
        ).first else { return }
        running.hide()
    }
}

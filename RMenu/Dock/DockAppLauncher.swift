import AppKit
import os

enum DockAppLauncher {

    private static let log = Logger(subsystem: "com.yeshan333.RMenu", category: "DockLauncher")

    private static var cycleCount = 0
    private static var cyclingBundleID: String?

    /// Toggle: if the app is frontmost, cycle its windows then hide after
    /// all windows have been shown. Otherwise launch/activate it.
    static func toggle(bundleID: String, appPath: String = "") {
        if isFrontmost(bundleID: bundleID) {
            cycleOrHide(bundleID: bundleID)
        } else {
            cycleCount = 0
            cyclingBundleID = nil
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
            AccessibilityActivator.activate(pid: running.processIdentifier)
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

    private static func cycleOrHide(bundleID: String) {
        guard let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleID
        ).first else { return }

        if cyclingBundleID != bundleID {
            cycleCount = 0
            cyclingBundleID = bundleID
        }

        let windowCount = AccessibilityActivator.windowCount(
            pid: running.processIdentifier
        )
        // Already cycled through all windows → hide
        if windowCount <= 1 || cycleCount >= windowCount - 1 {
            running.hide()
            cycleCount = 0
            cyclingBundleID = nil
            return
        }

        if AccessibilityActivator.cycleWindows(pid: running.processIdentifier) {
            cycleCount += 1
        } else {
            running.hide()
            cycleCount = 0
            cyclingBundleID = nil
        }
    }
}

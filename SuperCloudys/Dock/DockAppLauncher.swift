import AppKit
import os

@MainActor
enum DockAppLauncher {

    nonisolated private static let log = Logger(
        subsystem: "com.yeshan333.SuperCloudys", category: "DockLauncher"
    )

    private static var cycleCount = 0
    private static var cyclingBundleID: String?
    private static var cyclingWindowCount = 0

    /// Toggle: if the app is frontmost, cycle its windows then hide after
    /// all windows have been shown. Otherwise launch/activate it.
    static func toggle(bundleID: String, appPath: String = "") {
        if isFrontmost(bundleID: bundleID) {
            cycleOrHide(bundleID: bundleID)
        } else {
            cycleCount = 0
            cyclingBundleID = nil
            cyclingWindowCount = 0
            launchOrFocus(bundleID: bundleID, appPath: appPath)
        }
    }

    // MARK: - Private

    private static func isFrontmost(bundleID: String) -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    private static func launchOrFocus(bundleID: String, appPath: String) {
        guard let appURL = resolveAppURL(bundleID: bundleID, appPath: appPath) else {
            log.warning("Cannot launch \(bundleID, privacy: .public): no URL (path=\(appPath, privacy: .public))")
            return
        }

        // Always use NSWorkspace.shared.openApplication. It handles launching, unhiding,
        // and bringing the app to the front, avoiding macOS 14+ background activation restrictions.
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { app, error in
            if let error {
                log.error("openApplication failed for \(bundleID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            } else if let app = app {
                // As a fallback to ensure all windows are brought forward
                _ = AccessibilityActivator.activate(pid: app.processIdentifier)
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

        let windowCount = AccessibilityActivator.windowCount(
            pid: running.processIdentifier
        )
        if cyclingBundleID != bundleID || cyclingWindowCount != windowCount {
            cycleCount = 0
            cyclingBundleID = bundleID
            cyclingWindowCount = windowCount
        }

        // Already cycled through all windows → hide
        if windowCount <= 1 || cycleCount >= windowCount - 1 {
            running.hide()
            cycleCount = 0
            cyclingBundleID = nil
            cyclingWindowCount = 0
            return
        }

        if AccessibilityActivator.cycleWindows(pid: running.processIdentifier) {
            cycleCount += 1
        } else {
            running.hide()
            cycleCount = 0
            cyclingBundleID = nil
            cyclingWindowCount = 0
        }
    }
}

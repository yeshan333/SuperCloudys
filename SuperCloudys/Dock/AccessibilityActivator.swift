import AppKit
import ApplicationServices

enum AccessibilityActivator {

    private static let messagingTimeout: Float = 0.5

    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestTrust() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Sets the target app as frontmost via AXUIElement. Returns true on success.
    static func activate(pid: pid_t) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let app = applicationElement(pid: pid)
        let result = AXUIElementSetAttributeValue(
            app, kAXFrontmostAttribute as CFString, kCFBooleanTrue
        )
        return result == .success
    }

    static func windowCount(pid: pid_t) -> Int {
        guard AXIsProcessTrusted() else { return 0 }
        let app = applicationElement(pid: pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app, kAXWindowsAttribute as CFString, &value
        ) == .success, let windows = value as? [AXUIElement] else {
            return 0
        }
        return windows.count
    }

    /// Cycles to the next window of the given app.
    /// Returns true if a cycle was performed.
    static func cycleWindows(pid: pid_t) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let app = applicationElement(pid: pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app, kAXWindowsAttribute as CFString, &value
        ) == .success, let windows = value as? [AXUIElement],
              windows.count > 1 else {
            return false
        }

        var focusedRef: CFTypeRef?
        AXUIElementCopyAttributeValue(
            app, kAXFocusedWindowAttribute as CFString, &focusedRef
        )
        var targetIndex = 1
        if let focused = focusedRef {
            for (i, win) in windows.enumerated() {
                if CFEqual(focused as CFTypeRef, win) {
                    targetIndex = (i + 1) % windows.count
                    break
                }
            }
        }

        let target = windows[targetIndex]
        _ = AXUIElementSetAttributeValue(
            target, kAXMainAttribute as CFString, kCFBooleanTrue
        )
        let raised = AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        let frontmost = AXUIElementSetAttributeValue(
            app, kAXFrontmostAttribute as CFString, kCFBooleanTrue
        )
        return raised == .success && frontmost == .success
    }

    private static func applicationElement(pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        return app
    }
}

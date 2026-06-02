import AppKit
import ApplicationServices
import os

enum AccessibilityActivator {

    private static let log = Logger(subsystem: "com.yeshan333.RMenu", category: "AXActivator")

    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Sets the target app as frontmost via AXUIElement. Returns true on success.
    static func activate(pid: pid_t) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let app = AXUIElementCreateApplication(pid)
        let result = AXUIElementSetAttributeValue(
            app, kAXFrontmostAttribute as CFString, kCFBooleanTrue
        )
        return result == .success
    }

    static func windowCount(pid: pid_t) -> Int {
        guard AXIsProcessTrusted() else { return 0 }
        let app = AXUIElementCreateApplication(pid)
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
        let app = AXUIElementCreateApplication(pid)
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
        AXUIElementSetAttributeValue(
            target, kAXMainAttribute as CFString, kCFBooleanTrue
        )
        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(
            app, kAXFrontmostAttribute as CFString, kCFBooleanTrue
        )
        return true
    }
}

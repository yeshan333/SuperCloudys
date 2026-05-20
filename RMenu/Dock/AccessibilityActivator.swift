import AppKit
import ApplicationServices

/// Activates other apps via the Accessibility API. Bypasses macOS 14+
/// focus-stealing protection that rejects activations from sandboxed
/// LSUIElement helpers, but requires the user to grant "Accessibility"
/// in System Settings → Privacy & Security.
enum AccessibilityActivator {

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Prompts the user to grant Accessibility via the system dialog.
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
}

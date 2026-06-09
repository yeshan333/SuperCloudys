# BUG FIX RECORDS

This document tracks edge-case bugs, UI/UX issues, and their resolutions to avoid reintroducing them in future developments.

## 1. macOS 14+ Background App Activation Restriction
**Issue:** `Cmd + Number` to quickly activate/open Dock application windows failed silently.
**Root Cause:** Starting with macOS 14 (Sonoma), background apps (e.g. `LSUIElement` apps like SuperCloudys) are restricted from bringing other apps to the foreground via `NSRunningApplication.activate()`. The operation is intercepted by system policy and silently fails.
**Fix:** Replaced `running.activate()` with `NSWorkspace.shared.openApplication(at:configuration:completionHandler:)`. By setting `config.activates = true`, the system's `launchservicesd` safely brings the application to the foreground without triggering background activation policy violations.
**Code Reference:** `DockAppLauncher.swift` (`launchOrFocus` method)

## 2. Clipboard History List Selection Jumping (Arrow Keys)
**Issue:** Using `Up/Down` arrow keys to navigate the clipboard history caused the selection to randomly jump several items or skip sections.
**Root Cause:** The `EntryListView` visually grouped items by `createdAt` or `Pinned` status, but the `onKeyPress` navigation used the flat `filteredEntries` array, which was only partially sorted (or sorted primarily by insertion order instead of visual groupings). The discrepancy between the flat array index and the visual grouped index caused the jump.
**Fix:** 
- Enforced a strict visual-matching sort order in `ClipboardHistoryController.refreshFiltered()` (Pinned items first, then by `lastUsedAt ?? createdAt` descending).
- Updated `EntryListView.groupedByDay()` to explicitly group pinned items into a `"Pinned"` section, and use `lastUsedAt ?? createdAt` for the remaining items.
This guarantees the visual order and the array order are 100% identical.

## 3. Search Bar Auto-Focus Failure on Re-open
**Issue:** Pressing `Ctrl + H` opened the clipboard history popup, but the search `TextField` did not receive cursor focus automatically after the first time.
**Root Cause:** In SwiftUI macOS development, `.onAppear` only fires when the view is initially created. Since `ClipboardPanelController` uses `orderOut` to hide the panel and `makeKeyAndOrderFront` to show it, the underlying `NSHostingView` is never destroyed, so `.onAppear` is skipped on subsequent opens.
**Fix:** Added an `@Published var isPanelVisible` state to `ClipboardHistoryController` that toggles on `show()` and `hide()`. The `SearchBarView` observes this via `.onChange(of: isVisible)` to re-apply focus.

## 4. Search Bar Focus Timing Issue (Window Not Key Yet)
**Issue:** Even with `.onAppear` and `.onChange(of: isVisible)`, the text field sometimes failed to gain focus when the popup was opened.
**Root Cause:** SwiftUI's `@FocusState` requires the hosting window to be the active Key Window. When `makeKeyAndOrderFront` is called, the window might still be animating or transitioning. Setting the focus state instantly gets ignored by the system.
**Fix:** Wrapped the `isSearchFocused = true` assignment in `DispatchQueue.main.asyncAfter(deadline: .now() + 0.1)` inside both `.onAppear` and `.onChange`. The 0.1s delay ensures the window is ready to accept keyboard focus.

## 5. App Launch Silently Failing on First Install (Missing Accessibility Prompt)
**Issue:** When a user installed the app for the very first time, the core features (`Cmd+Number`, `Ctrl+H` pasting) did not work, and the user had no feedback on what was wrong.
**Root Cause:** SuperCloudys is a menu bar app (`LSUIElement`). It does not show a main window on launch. Furthermore, it relied on Accessibility permissions (AX API) but never explicitly prompted the user for them.
**Fix:** Added an asynchronous call to `AccessibilityActivator.requestTrust()` inside `SuperCloudysApp.init()`. This proactively triggers the macOS system dialog "SuperCloudys would like to control this computer using accessibility features" on the first launch, guiding the user to grant necessary permissions.

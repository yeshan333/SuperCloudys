# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SuperCloudys (formerly RMenu) is a macOS desktop productivity app: Finder right-click menu enhancement + Dock global shortcuts (Cmd+1~0) + clipboard history (Ctrl+H) + menu bar management. Requires macOS 14.0+, Swift 5.9, Xcode 15+.

## Build & Run

```bash
# Generate Xcode project (required before any build)
brew install xcodegen   # one-time
xcodegen generate

# One-click local build with stable code signing (recommended for dev)
./scripts/install-local.sh

# Manual Release build
xcodebuild \
  -project SuperCloudys.xcodeproj \
  -scheme SuperCloudys \
  -configuration Release \
  build \
  CODE_SIGN_IDENTITY="SuperCloudys Local Dev" \
  CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES \
  CONFIGURATION_BUILD_DIR="$(pwd)/build"
```

## Tests

```bash
xcodegen generate
xcodebuild test \
  -project SuperCloudys.xcodeproj \
  -scheme SuperCloudysTests \
  -destination 'platform=macOS'
```

Test fixtures live in `SuperCloudysTests/Fixtures/`. The app entry point skips clipboard monitoring during tests via `XCTestConfigurationFilePath` env check.

## Architecture

The project has **three targets** defined in `project.yml` (XcodeGen):

### SuperCloudys (main app, unsandboxed)
Menu bar-only app (`MenuBarExtra`) — no main window. Subsystems:
- **Dock/** — Global Cmd+1~0 shortcuts via Carbon `RegisterEventHotKey`. `DockMonitor` watches the Dock plist via `DispatchSourceFileSystemObject` (not polling). `DockAppLauncher` handles activate/hide toggle with AXUIElement window cycling. `AccessibilityActivator` bypasses macOS 14+ focus protection.
- **Clipboard/** — Clipboard history with Ctrl+H floating panel. `ClipboardMonitorService` polls `NSPasteboard` on a background GCD timer. `ClipboardStore` persists entries to disk (JSON + images). `ClipboardPanelController` manages the NSPanel. Views are in `Clipboard/Views/`.
- **Services/** — `AppIconCache` (async icon loading), `ExtensionStatus` (Finder extension state), `LoginItemManager` (`SMAppService`), `IconPrewarmer`.
- **MenuBar/** — SwiftUI views for the menu bar dropdown.

### SuperCloudysExtension (Finder Sync extension, sandboxed)
`FIFinderSync` subclass injecting right-click menu items. Uses `MenuSnapshot` pattern: background utility queue pre-builds menu data, `menu(for:)` on main thread only assembles NSMenu (< 0.5ms). Actions in `Actions/` subfolder.

### Shared/ (compiled into both targets)
`Constants.swift` (bundle IDs, built-in `ExternalApp` list), `CustomAppStore.swift` (JSON persistence with mtime cache + NSLock), `DockShortcutSettings.swift`.

## Key Design Decisions

- **No sandbox on main app** — required for Accessibility API (AXUIElement) to manipulate other apps' windows.
- **Stable code signing** — `install-local.sh` creates a persistent self-signed cert so TCC (Accessibility) permissions survive rebuilds. Ad-hoc signing resets TCC every build.
- **Event-driven Dock monitoring** — `DispatchSourceFileSystemObject` on the Dock plist, not polling. Zero CPU when Dock is unchanged.
- **`CustomAppStore` shared config** — JSON file at `~/Library/Application Support/SuperCloudys/custom_apps.json` read by both main app and extension. mtime-based cache invalidation, `NSLock` with file I/O outside the lock.
- **Carbon hotkeys** — `RegisterEventHotKey` doesn't require Accessibility permission for registration itself; Accessibility is only needed for AXUIElement-based activation.

## CI/CD

GitHub Actions (`.github/workflows/build.yml`): push a `v*` tag to trigger Release build + DMG creation + GitHub Release. Also supports manual dispatch.

## Scripts

- `scripts/install-local.sh` — full dev cycle: cert setup → Release build → kill running → install to ~/Applications → launch
- `scripts/create-dmg.sh` — package .app into .dmg
- `scripts/diagnose_rightclick.sh` — diagnose Finder right-click slowness (samples Finder, checks os_log, inspects spindump)

## Language

UI strings and comments are in Chinese (Simplified). Follow this convention.

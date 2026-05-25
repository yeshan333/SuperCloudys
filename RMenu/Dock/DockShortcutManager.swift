import AppKit
import Carbon.HIToolbox
import os

/// Registers global Cmd+1..Cmd+9, Cmd+0 hotkeys via Carbon Event Manager,
/// dispatching to DockAppLauncher when fired.
final class DockShortcutManager {

    static let shared = DockShortcutManager()

    private let log = Logger(subsystem: "com.yeshan333.RMenu", category: "DockShortcut")
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlers: [UInt32: (bundleID: String, appPath: String)] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    private static let signature: OSType = 0x524D4E55 // 'RMNU'

    private init() {
        installEventHandler()
    }

    deinit {
        unregisterAll()
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }

    // MARK: - Public

    func register(apps: [DockApp]) {
        unregisterAll()
        for (index, app) in apps.prefix(DockApp.maxShortcutApps).enumerated() {
            guard let keyCode = Self.keyCode(forIndex: index) else { continue }
            register(keyCode: keyCode, bundleID: app.bundleID, appPath: app.appPath)
        }
    }

    func unregisterAll() {
        for ref in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        handlers.removeAll()
        nextID = 1
    }

    // MARK: - Private

    private func register(keyCode: UInt32, bundleID: String, appPath: String) {
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: nextID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            UInt32(cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            log.warning("RegisterEventHotKey failed (status=\(status)) for keyCode=\(keyCode), bundle=\(bundleID)")
            return
        }
        hotKeyRefs.append(ref)
        handlers[nextID] = (bundleID, appPath)
        nextID += 1
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let eventRef, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard err == noErr else { return err }
            let manager = Unmanaged<DockShortcutManager>
                .fromOpaque(userData)
                .takeUnretainedValue()
            if let entry = manager.handlers[hotKeyID.id] {
                // Run synchronously so the Carbon-granted activation token
                // doesn't expire before we call activate().
                DockAppLauncher.toggle(bundleID: entry.bundleID, appPath: entry.appPath)
            }
            return noErr
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )
        if status != noErr {
            log.error("InstallEventHandler failed (status=\(status)); hotkeys will not fire")
        }
    }

    private static func keyCode(forIndex index: Int) -> UInt32? {
        let codes: [Int] = [
            kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3,
            kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6,
            kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
            kVK_ANSI_0
        ]
        guard index >= 0, index < codes.count else { return nil }
        return UInt32(codes[index])
    }
}

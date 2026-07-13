import AppKit
import Carbon.HIToolbox
import os

/// Registers global Cmd+1..Cmd+9, Cmd+0 hotkeys via Carbon Event Manager,
/// dispatching to DockAppLauncher when fired.
final class DockShortcutManager: @unchecked Sendable {

    static let shared = DockShortcutManager()

    private let log = Logger(subsystem: "com.yeshan333.SuperCloudys", category: "DockShortcut")
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlers: [UInt32: (bundleID: String, appPath: String)] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    private static let signature: OSType = 0x524D4E55 // 'RMNU'

    private init() {
        _ = installEventHandler()
    }

    deinit {
        unregisterAll()
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }

    // MARK: - Public

    func register(apps: [DockApp]) -> [String] {
        unregisterAll()
        let handlerStatus = installEventHandler()
        guard handlerStatus == noErr else {
            return ["事件处理器安装失败（\(handlerStatus)）"]
        }
        var failures: [String] = []
        for (index, app) in apps.prefix(DockApp.maxShortcutApps).enumerated() {
            guard let keyCode = Self.keyCode(forIndex: index) else { continue }
            if let status = register(keyCode: keyCode, bundleID: app.bundleID, appPath: app.appPath) {
                failures.append("⌘\(app.shortcutLabel ?? "?") \(app.name)（\(status)）")
            }
        }
        return failures
    }

    func unregisterAll() {
        for ref in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        handlers.removeAll()
        nextID = 1
    }

    // MARK: - Private

    private func register(keyCode: UInt32, bundleID: String, appPath: String) -> OSStatus? {
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
            return status
        }
        hotKeyRefs.append(ref)
        handlers[nextID] = (bundleID, appPath)
        nextID += 1
        return nil
    }

    private func installEventHandler() -> OSStatus {
        guard eventHandler == nil else { return noErr }
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
            guard hotKeyID.signature == DockShortcutManager.signature,
                  let entry = manager.handlers[hotKeyID.id] else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async {
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
        return status
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

import Carbon.HIToolbox
import os

final class ClipboardHotkeyManager {

    static let shared = ClipboardHotkeyManager()

    private let log = Logger(subsystem: "com.yeshan333.SuperCloudys", category: "ClipboardHotkey")
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private static let signature: OSType = 0x434C4950 // 'CLIP'
    private static let hotkeyID: UInt32 = 100

    private init() {}

    func register() {
        guard hotKeyRef == nil else { return }
        installEventHandler()

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotkeyID)
        var ref: EventHotKeyRef?
        // kVK_ANSI_H = 0x04, controlKey modifier
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_H),
            UInt32(controlKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            hotKeyRef = ref
            log.info("Registered Ctrl+H clipboard history hotkey")
        } else {
            log.warning("Failed to register Ctrl+H hotkey (status=\(status))")
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    // MARK: - Private

    private func installEventHandler() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, eventRef, _ in
            guard let eventRef else { return noErr }
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

            guard hotKeyID.signature == ClipboardHotkeyManager.signature,
                  hotKeyID.id == ClipboardHotkeyManager.hotkeyID else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async {
                ClipboardPanelController.shared.toggle()
            }
            return noErr
        }

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &eventHandler
        )
        if status != noErr {
            log.error("InstallEventHandler for clipboard hotkey failed (status=\(status))")
        }
    }
}

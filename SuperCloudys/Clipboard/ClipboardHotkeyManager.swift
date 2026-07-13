import Carbon.HIToolbox
import Combine
import os

@MainActor
final class ClipboardHotkeyManager: ObservableObject {

    static let shared = ClipboardHotkeyManager()

    private let log = Logger(subsystem: "com.yeshan333.SuperCloudys", category: "ClipboardHotkey")
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    @Published private(set) var registrationError: String?

    private static let signature: OSType = 0x434C4950 // 'CLIP'
    private static let hotkeyID: UInt32 = 100

    private init() {}

    func register() {
        guard hotKeyRef == nil else { return }
        guard installEventHandler() else { return }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotkeyID)
        var ref: EventHotKeyRef?
        // Cmd+Shift+V avoids stealing Ctrl+H/backspace from terminals.
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            hotKeyRef = ref
            registrationError = nil
            log.info("Registered Cmd+Shift+V clipboard history hotkey")
        } else {
            registrationError = "Cmd+Shift+V 注册失败（\(status)），可能与其他应用冲突"
            log.warning("Failed to register Cmd+Shift+V hotkey (status=\(status))")
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

    private func installEventHandler() -> Bool {
        guard eventHandler == nil else { return true }

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
            registrationError = "剪贴板快捷键事件处理器安装失败（\(status)）"
            log.error("InstallEventHandler for clipboard hotkey failed (status=\(status))")
            return false
        }
        return true
    }
}

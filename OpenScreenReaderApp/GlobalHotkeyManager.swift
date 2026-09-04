import Carbon.HIToolbox

struct HotkeyShortcut: Equatable, Sendable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let displayName: String

    static let readScreenRegion = HotkeyShortcut(
        keyCode: UInt32(kVK_ANSI_R),
        carbonModifiers: UInt32(controlKey | optionKey),
        displayName: "⌃⌥R"
    )
}

enum HotkeyRegistration: Equatable, Sendable {
    case inactive
    case registered
    case conflict
    case failed(OSStatus)
}

@MainActor
protocol HotkeyManaging: AnyObject {
    var onPress: (() -> Void)? { get set }

    func register(_ shortcut: HotkeyShortcut) -> HotkeyRegistration
    func unregister()
}

@MainActor
final class GlobalHotkeyManager: HotkeyManaging {
    var onPress: (() -> Void)?

    nonisolated(unsafe) private var eventHandlerRef: EventHandlerRef?
    nonisolated(unsafe) private var hotkeyRef: EventHotKeyRef?

    deinit {
        if let hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func register(_ shortcut: HotkeyShortcut) -> HotkeyRegistration {
        unregister()

        guard installEventHandlerIfNeeded() == noErr else {
            return .failed(OSStatus(eventInternalErr))
        }

        let hotkeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        switch status {
        case noErr:
            return .registered
        case OSStatus(eventHotKeyExistsErr):
            hotkeyRef = nil
            return .conflict
        default:
            hotkeyRef = nil
            return .failed(status)
        }
    }

    func unregister() {
        if let hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }
    }

    private func installEventHandlerIfNeeded() -> OSStatus {
        guard eventHandlerRef == nil else {
            return noErr
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()

        return InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )
    }

    nonisolated private static let eventHandler: EventHandlerUPP = {
        _, event, userData in
        guard let event, let userData else {
            return OSStatus(eventNotHandledErr)
        }

        var hotkeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )
        guard status == noErr,
              hotkeyID.signature == GlobalHotkeyManager.signature,
              hotkeyID.id == 1 else {
            return OSStatus(eventNotHandledErr)
        }

        let manager = Unmanaged<GlobalHotkeyManager>
            .fromOpaque(userData)
            .takeUnretainedValue()
        Task { @MainActor in
            manager.onPress?()
        }
        return noErr
    }

    nonisolated private static let signature: OSType = 0x4F_53_52_52
}

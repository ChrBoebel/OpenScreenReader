import Carbon.HIToolbox

struct HotkeyShortcut: Equatable, Sendable {
    let keyCode: UInt32?
    let carbonModifiers: UInt32
    let displayName: String

    @MainActor
    static var readScreenRegion: HotkeyShortcut {
        let modifiers = UInt32(cmdKey | shiftKey)
        return HotkeyShortcut(keyCode: keyCode(for: "Y", modifiers: modifiers),
                              carbonModifiers: modifiers, displayName: "⌘⇧Y")
    }

    // Carbon registers physical key codes. Resolve the requested character using
    // the layout at registration, including Command mappings (e.g. Dvorak-QWERTY).
    // No keyboard events are observed or synthesized by this lookup.
    @MainActor
    static func keyCode(
        for character: String, modifiers: UInt32, source: TISInputSource? = nil
    ) -> UInt32? {
        let source = source ?? TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        return withExtendedLifetime(data) {
            let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
            for code in UInt16(0)..<128 {
                var deadKeyState: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 8)
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown),
                    (modifiers >> 8) & 0xFF, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
                    characters.count, &length, &characters)
                // Command layouts can return lowercase even when Shift is present.
                if status == noErr,
                   String(utf16CodeUnits: characters, count: length).lowercased() == character.lowercased() {
                    return UInt32(code)
                }
            }
            return nil
        }
    }
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

        guard let keyCode = shortcut.keyCode else { return .failed(OSStatus(paramErr)) }

        guard installEventHandlerIfNeeded() == noErr else {
            return .failed(OSStatus(eventInternalErr))
        }

        let hotkeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            keyCode,
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

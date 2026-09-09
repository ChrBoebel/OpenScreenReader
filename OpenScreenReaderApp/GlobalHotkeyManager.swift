import Carbon.HIToolbox
import Foundation

struct ShortcutConfiguration: Codable, Equatable, Sendable {
    var key: String
    var modifiers: UInt32

    static let `default` = ShortcutConfiguration(key: "Y", modifiers: UInt32(cmdKey | shiftKey))
    static let queueDefault = ShortcutConfiguration(key: "Y", modifiers: UInt32(cmdKey | optionKey | shiftKey))
    static let availableKeys = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").map(String.init) + ["Space"]
    static let supportedModifiers = UInt32(cmdKey | shiftKey | optionKey | controlKey)

    var isValid: Bool {
        Self.availableKeys.contains(key)
            && modifiers & ~Self.supportedModifiers == 0
            && modifiers & UInt32(cmdKey | optionKey | controlKey) != 0
    }

    var displayName: String {
        [(UInt32(controlKey), "⌃"), (UInt32(optionKey), "⌥"),
         (UInt32(cmdKey), "⌘"), (UInt32(shiftKey), "⇧")]
            .filter { modifiers & $0.0 != 0 }.map(\.1).joined() + key
    }

    @MainActor
    func resolvedShortcut(source: TISInputSource? = nil) -> HotkeyShortcut {
        // Resolve the base key, not Option's alternate character or Shift's symbol.
        // Command mappings still matter for layouts such as Dvorak-QWERTY.
        HotkeyShortcut(keyCode: isValid ? HotkeyShortcut.keyCode(
            for: key == "Space" ? " " : key,
            modifiers: modifiers & UInt32(cmdKey), source: source) : nil,
            carbonModifiers: modifiers, displayName: displayName)
    }
}

@MainActor
protocol ShortcutStoring {
    func load() -> ShortcutConfiguration?
    func save(_ configuration: ShortcutConfiguration)
}

@MainActor
final class UserDefaultsShortcutStore: ShortcutStoring {
    static let preferenceKey = "readingShortcut.v1"
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults? = nil, preferenceKey: String = UserDefaultsShortcutStore.preferenceKey) {
        key = preferenceKey
        if let defaults { self.defaults = defaults; return }
        #if DEBUG
        // UI tests must never overwrite the user's real shortcut preference.
        if let suite = ProcessInfo.processInfo.environment["OSR_SHORTCUT_TEST_SUITE"],
           suite.hasPrefix("com.christopherbobel.OpenScreenReader.uitests."),
           let testDefaults = UserDefaults(suiteName: suite) {
            self.defaults = testDefaults
            return
        }
        #endif
        self.defaults = .standard
    }

    func load() -> ShortcutConfiguration? {
        guard let data = defaults.data(forKey: key),
              let configuration = try? JSONDecoder().decode(ShortcutConfiguration.self, from: data),
              configuration.isValid else { return nil }
        return configuration
    }

    func save(_ configuration: ShortcutConfiguration) {
        guard configuration.isValid, let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: key)
    }
}

struct HotkeyShortcut: Equatable, Sendable {
    let keyCode: UInt32?
    let carbonModifiers: UInt32
    let displayName: String

    @MainActor
    static var readScreenRegion: HotkeyShortcut {
        ShortcutConfiguration.default.resolvedShortcut()
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
    private var registeredShortcut: HotkeyShortcut?
    private var activeEventID: UInt32?
    private static var nextEventID: UInt32 = 0

    deinit {
        if let hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func register(_ shortcut: HotkeyShortcut) -> HotkeyRegistration {
        if registeredShortcut == shortcut { return .registered }
        guard let keyCode = shortcut.keyCode else { return .failed(OSStatus(paramErr)) }

        guard installEventHandlerIfNeeded() == noErr else {
            return .failed(OSStatus(eventInternalErr))
        }

        guard Self.nextEventID < UInt32.max else { return .failed(OSStatus(eventInternalErr)) }
        Self.nextEventID += 1
        let hotkeyID = EventHotKeyID(signature: Self.signature, id: Self.nextEventID)
        var candidateRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            shortcut.carbonModifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &candidateRef
        )

        switch status {
        case noErr:
            // Acquire the replacement before releasing the existing cancel shortcut.
            unregister()
            hotkeyRef = candidateRef
            registeredShortcut = shortcut
            activeEventID = hotkeyID.id
            return .registered
        case OSStatus(eventHotKeyExistsErr):
            return .conflict
        default:
            return .failed(status)
        }
    }

    func unregister() {
        activeEventID = nil
        registeredShortcut = nil
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
              hotkeyID.signature == GlobalHotkeyManager.signature else {
            return OSStatus(eventNotHandledErr)
        }

        let manager = Unmanaged<GlobalHotkeyManager>
            .fromOpaque(userData)
            .takeUnretainedValue()
        let eventID = hotkeyID.id
        // Carbon application events are delivered on the main event loop.
        guard MainActor.assumeIsolated({ manager.activeEventID == eventID }) else {
            return OSStatus(eventNotHandledErr)
        }
        Task { @MainActor in
            guard manager.activeEventID == eventID else { return }
            manager.onPress?()
        }
        return noErr
    }

    nonisolated private static let signature: OSType = 0x4F_53_52_52
}

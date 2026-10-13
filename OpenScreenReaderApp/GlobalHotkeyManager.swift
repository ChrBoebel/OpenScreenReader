import Carbon.HIToolbox
import Foundation
import AppKit

struct ShortcutConfiguration: Codable, Equatable, Sendable {
    var key: String
    var modifiers: UInt32

    static let `default` = ShortcutConfiguration(key: "R", modifiers: UInt32(optionKey))
    static let previousDefault = ShortcutConfiguration(key: "Y", modifiers: UInt32(cmdKey | shiftKey))
    static let dictationDefault = ShortcutConfiguration(key: "Space", modifiers: UInt32(optionKey | shiftKey))
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

    /// Converts a keystroke from a shortcut field. `character` is the key without
    /// modifiers applied. Returns nil for keys a global shortcut cannot use; the
    /// result may still be invalid (for example Shift alone) so the field can explain why.
    static func recorded(character: String, flags: NSEvent.ModifierFlags) -> ShortcutConfiguration? {
        let key = character == " " ? "Space" : character.uppercased()
        guard availableKeys.contains(key) else { return nil }
        let modifiers = [(NSEvent.ModifierFlags.command, cmdKey), (.option, optionKey),
                         (.control, controlKey), (.shift, shiftKey)]
            .filter { flags.contains($0.0) }
            .reduce(UInt32(0)) { $0 | UInt32($1.1) }
        return ShortcutConfiguration(key: key, modifiers: modifiers)
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

/// Only gesture timing, never key text. A short single Fn tap is discarded;
/// double-tap locks recording, and a third quick tap discards it.
struct FnDictationGesture {
    enum Action: Equatable, Sendable { case start, lock, finish, cancel }
    private enum Mode { case idle, holding, waiting, locked }
    private var mode = Mode.idle
    private var down = false
    private var ignoreRelease = false
    private var pressedAt = 0.0
    private var lockedAt = 0.0
    var isActive: Bool { mode != .idle }

    mutating func reset() { self = Self() }
    mutating func press(at time: Double) -> [Action] {
        guard !down else { return [] }
        let expired = expire(at: time)
        down = true
        ignoreRelease = false
        pressedAt = time
        switch mode {
        case .idle: mode = .holding; return expired + [.start]
        case .waiting:
            mode = .locked; lockedAt = time; ignoreRelease = true
            return [.lock]
        case .holding, .locked: return []
        }
    }
    mutating func release(at time: Double) -> [Action] {
        guard down else { return [] }
        down = false
        if ignoreRelease { ignoreRelease = false; return [] }
        switch mode {
        case .holding:
            if time - pressedAt < 0.5 { mode = .waiting; return [] }
            mode = .idle; return [.finish]
        case .locked:
            mode = .idle
            return time - lockedAt < 0.5 ? [.cancel] : [.finish]
        case .idle, .waiting: return []
        }
    }
    mutating func space(at time: Double) -> [Action] {
        guard down else { return [] }
        ignoreRelease = true
        switch mode {
        case .holding, .waiting:
            mode = .locked; lockedAt = time; return [.lock]
        case .locked:
            mode = .idle
            return time - lockedAt < 0.5 ? [.cancel] : [.finish]
        case .idle: return []
        }
    }
    mutating func otherKey() -> [Action] {
        guard down else { return [] }
        ignoreRelease = true
        if mode == .holding || mode == .waiting { mode = .idle; return [.cancel] }
        return []
    }
    mutating func expire(at time: Double) -> [Action] {
        if mode == .waiting, time - pressedAt >= 0.5 {
            mode = .idle; return [.cancel]
        }
        return []
    }
}

/// An active tap is needed to consume Fn/Space so macOS does not also open its
/// emoji/dictation UI. Only Fn gesture metadata is retained, never typed text.
@MainActor
final class FnDictationShortcuts {
    var onAction: ((FnDictationGesture.Action) -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var gesture = FnDictationGesture()
    private var generation = UUID()
    private var ownsSpace = false
    private var deliveringAction = false
    var isAvailable: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    isolated deinit { stop() }

    func start() {
        guard tap == nil, AXIsProcessTrusted(), !IsSecureEventInputEnabled() else { return }
        let mask = [CGEventType.flagsChanged, .keyDown, .keyUp]
            .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                // Installed exclusively on the main run loop, like EscapeMonitor.
                let consumed = MainActor.assumeIsolated {
                    Unmanaged<FnDictationShortcuts>.fromOpaque(context).takeUnretainedValue()
                        .handle(type: type, event: event)
                }
                return consumed ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
            let runLoopSource = CFMachPortCreateRunLoopSource(nil, created, 0) else { return }
        tap = created
        source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        let health = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.isAvailable || !AXIsProcessTrusted() || IsSecureEventInputEnabled() {
                    let active = self.gesture.isActive
                    self.stop()
                    if active { _ = self.onAction?(.cancel) }
                    return
                }
                self.enqueue(self.gesture.expire(at: ProcessInfo.processInfo.systemUptime))
            }
        }
        timer = health
        RunLoop.main.add(health, forMode: .common)
    }
    func resetGesture() {
        guard !deliveringAction else { return }
        generation = UUID()
        gesture.reset()
    }
    func stop() {
        resetGesture()
        timer?.invalidate(); timer = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil; source = nil; ownsSpace = false
    }
    private func enqueue(_ actions: [FnDictationGesture.Action]) {
        guard !actions.isEmpty else { return }
        let current = generation
        // Keep AX lookups and microphone startup out of the event-tap callback.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == current, self.isAvailable else { return }
            for action in actions {
                self.deliveringAction = true
                let accepted = self.onAction?(action) == true
                self.deliveringAction = false
                if !accepted { self.resetGesture(); break }
            }
        }
    }
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let active = gesture.isActive
            resetGesture()
            if active { _ = onAction?(.cancel) }
            return false
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let fn = event.flags.contains(.maskSecondaryFn)
        let others = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        let time = ProcessInfo.processInfo.systemUptime
        if type == .flagsChanged, code == 63 {
            if !others.isEmpty {
                enqueue(gesture.otherKey())
                if !fn { enqueue(gesture.release(at: time)) }
                return false
            }
            enqueue(fn ? gesture.press(at: time) : gesture.release(at: time))
            return true
        }
        if type == .keyUp, code == 49, ownsSpace { ownsSpace = false; return true }
        if type == .keyDown, code == 49, fn, others.isEmpty {
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                enqueue(gesture.space(at: time))
            }
            ownsSpace = true
            return true
        }
        if (type == .keyDown || type == .flagsChanged), fn {
            enqueue(gesture.otherKey())
        }
        return false
    }
}

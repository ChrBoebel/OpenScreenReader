import AppKit
import Carbon.HIToolbox

enum EscapeMonitorFailure: Error, LocalizedError {
    case permissionRequired
    case unavailable

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            String(localized: "Allow Input Monitoring in Settings so Escape can stop capture and text recognition while another app is active.")
        case .unavailable:
            String(localized: "Global Escape is unavailable, possibly because Secure Input is active. The operation was stopped.")
        }
    }
}

@MainActor
protocol EscapeMonitoring: AnyObject {
    func start(onEscape: @escaping () -> Void, onUnavailable: @escaping () -> Void) throws
    func stop()
}

/// A listen-only tap on the main run loop. No key data leaves the callback.
@MainActor
final class EscapeMonitor: EscapeMonitoring {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var healthTimer: Timer?
    private var onEscape: (() -> Void)?
    private var onUnavailable: (() -> Void)?

    isolated deinit { stop() }

    func start(onEscape: @escaping () -> Void, onUnavailable: @escaping () -> Void) throws {
        stop()
        guard CGPreflightListenEventAccess() else { throw EscapeMonitorFailure.permissionRequired }
        guard !IsSecureEventInputEnabled() else { throw EscapeMonitorFailure.unavailable }
        self.onEscape = onEscape
        self.onUnavailable = onUnavailable
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                // This callback is installed exclusively on the main run loop.
                MainActor.assumeIsolated {
                    let monitor = Unmanaged<EscapeMonitor>.fromOpaque(context).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        monitor.onUnavailable?()
                    } else if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 53 {
                        monitor.onEscape?()
                    }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            stop()
            throw EscapeMonitorFailure.unavailable
        }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let tap = self.tap else { return }
                if IsSecureEventInputEnabled() || !CGEvent.tapIsEnabled(tap: tap) || !CGPreflightListenEventAccess() {
                    self.onUnavailable?()
                }
            }
        }
        healthTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        healthTimer?.invalidate()
        healthTimer = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        onEscape = nil
        onUnavailable = nil
    }
}

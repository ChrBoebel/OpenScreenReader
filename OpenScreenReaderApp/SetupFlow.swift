import AppKit
import Combine
import SwiftUI

/// One screen per decision: reading first, dictation offered rather than required.
enum SetupStep: Hashable {
    case welcome, permission(SaywingPermission), readingModel, readingShortcuts, tryReading, dictationOffer, dictationModel, dictationShortcuts, tryDictation, done

    var previewName: String {
        switch self {
        case .readingModel: "readingModel"
        case .readingShortcuts: "readingShortcuts"
        case .dictationModel: "dictationModel"
        case .dictationShortcuts: "dictationShortcuts"
        case .welcome: "welcome"
        case let .permission(permission): permission.rawValue
        case .tryReading: "try-reading"
        case .dictationOffer: "dictation-offer"
        case .tryDictation: "try-dictation"
        case .done: "done"
        }
    }
}

extension SetupStep {
    init?(checkpoint: String) {
        if let permission = SaywingPermission(rawValue: checkpoint) { self = .permission(permission); return }
        switch checkpoint {
        case "welcome": self = .welcome
        case "readingModel": self = .readingModel
        case "readingShortcuts": self = .readingShortcuts
        case "readingTest", "try-reading": self = .tryReading
        case "dictation-offer": self = .dictationOffer
        case "dictationModel": self = .dictationModel
        case "dictationShortcuts": self = .dictationShortcuts
        case "dictationTest", "try-dictation": self = .tryDictation
        case "done": self = .done
        default: return nil
        }
    }
}

enum SetupEntry { case automatic, dictation }

/// Navigation is reconciled with live grants; model and shortcut choices always remain explicit.
struct SetupPlan {
    let dictationAvailable: Bool
    var wantsDictation = false

    private var path: [SetupStep] {
        var steps: [SetupStep] = [.welcome] + SaywingPermission.reading.map(SetupStep.permission) + [.readingModel, .readingShortcuts, .tryReading]
        if dictationAvailable {
            steps.append(.dictationOffer)
            if wantsDictation { steps += SaywingPermission.dictation.map(SetupStep.permission) + [.dictationModel, .dictationShortcuts, .tryDictation] }
        }
        return steps + [.done]
    }

    func first(granted: Set<SaywingPermission>, entry: SetupEntry = .automatic) -> SetupStep {
        if entry == .dictation, dictationAvailable {
            var plan = self
            plan.wantsDictation = true
            return plan.next(after: .dictationOffer, granted: granted)
        }
        return granted.isEmpty ? .welcome : next(after: .welcome, granted: granted)
    }

    func next(after step: SetupStep, granted: Set<SaywingPermission>) -> SetupStep {
        let steps = path
        guard let index = steps.firstIndex(of: step) else { return .done }
        return steps[(index + 1)...].first { Self.isUseful($0, granted: granted) } ?? .done
    }

    private static func isUseful(_ step: SetupStep, granted: Set<SaywingPermission>) -> Bool {
        switch step {
        case let .permission(permission): !granted.contains(permission)
        case .tryReading: granted.isSuperset(of: SaywingPermission.reading)
        case .tryDictation: granted.contains(.microphone)
        case .welcome, .readingModel, .readingShortcuts, .dictationOffer, .dictationModel, .dictationShortcuts, .done: true
        }
    }
}

/// The reading test's result, from the real pipeline status. Only speech that
/// actually played counts as success.
enum ReadingTrial: Equatable {
    case waiting, working, speaking, heard, noText, failed

    func advanced(by status: AppStatus, foundText: Bool?) -> ReadingTrial {
        switch status {
        case .selecting, .capturing, .recognizing, .synthesizing: self == .speaking ? .speaking : .working
        case .speaking: .speaking
        case .waiting: self
        case .stopped: self == .speaking ? .heard : self == .working ? .waiting : self
        case .ready:
            switch self {
            case .speaking: .heard
            case .working: foundText == false ? .noText : .waiting
            default: self
            }
        case .error: .failed
        }
    }
}

@MainActor
final class SetupFlowController: ObservableObject {
    @Published private(set) var step: SetupStep
    /// The grant the user asked for and Saywing is waiting on in System Settings.
    @Published private(set) var awaiting: SaywingPermission?
    @Published private(set) var celebrating: SaywingPermission?
    @Published private(set) var suggestsRelaunch = false
    @Published private(set) var trial = ReadingTrial.waiting
    @Published private(set) var readingConfirmed = false
    @Published private(set) var movesForward = true
    let permissions: PermissionStatus
    var onReturn: (() -> Void)?

    static let checkpointKey = "setupProgress.v1"
    private let preferences: UserDefaults
    private weak var model: AppModel?
    private var plan: SetupPlan
    private var history: [SetupStep] = []
    private var waitTask: Task<Void, Never>?
    private var advanceTask: Task<Void, Never>?
    private var subscriptions: Set<AnyCancellable> = []
    private var activationObserver: NSObjectProtocol?
    private let guide = SystemSettingsGuide()
    private let pointer = MenuBarPointer()

    init(model: AppModel, permissions: PermissionStatus = PermissionStatus(), entry: SetupEntry = .automatic, start: SetupStep? = nil) {
        self.preferences = model.preferences
        self.model = model
        self.permissions = permissions
        let saved = model.preferences.dictionary(forKey: Self.checkpointKey)
        let restored = (saved?["step"] as? String).flatMap(SetupStep.init(checkpoint:))
        let candidate = start ?? (entry == .automatic || restored.map(SetupPlan.dictationSteps.contains) == true ? restored : nil)
        var plan = SetupPlan(dictationAvailable: model.dictation != nil)
        if entry == .dictation || candidate.map(SetupPlan.dictationSteps.contains) == true { plan.wantsDictation = true }
        plan.wantsDictation = plan.wantsDictation || (saved?["wantsDictation"] as? Bool ?? false)
        self.plan = plan
        step = candidate ?? plan.first(granted: permissions.granted, entry: entry)
        if case let .permission(permission) = step, permissions.isGranted(permission) {
            step = plan.next(after: step, granted: permissions.granted)
        }
        if step == .tryReading, let missing = SaywingPermission.reading.first(where: { !permissions.isGranted($0) }) {
            step = .permission(missing)
        } else if step == .tryDictation, !permissions.isGranted(.microphone) { step = .permission(.microphone) }
        if let permission = (saved?["waitingFor"] as? String).flatMap(SaywingPermission.init(rawValue:)),
           step == .permission(permission), !permissions.isGranted(permission) {
            awaiting = permission
            suggestsRelaunch = permission == .screenRecording
        }
        persistCheckpoint()
        permissions.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        // @Published delivers the new value before it is stored.
        permissions.$granted.sink { [weak self] granted in self?.grantsChanged(granted) }.store(in: &subscriptions)
        model.$status.sink { [weak self, weak model] status in
            guard let self, self.step == .tryReading else { return }
            self.observeReading(status, foundText: model?.lastOCRSummary.map { $0.characterCount > 0 })
        }.store(in: &subscriptions)
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.returnedToSaywing() } }
    }

    isolated deinit {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        waitTask?.cancel()
        advanceTask?.cancel()
    }

    func persistCheckpoint(resume: Bool = true) {
        var saved: [String: Any] = ["step": step.previewName, "resume": resume, "wantsDictation": plan.wantsDictation]
        if let awaiting { saved["waitingFor"] = awaiting.rawValue }
        preferences.set(saved, forKey: Self.checkpointKey)
        preferences.synchronize()
    }

    var canGoBack: Bool { !history.isEmpty || [.readingShortcuts, .dictationShortcuts, .tryReading, .tryDictation].contains(step) }
    var shortcut: String { model?.shortcutConfiguration.displayName ?? "" }
    var wantsDictation: Bool { plan.wantsDictation }
    var missingPermissions: [SaywingPermission] {
        let needed = SaywingPermission.reading + (plan.wantsDictation ? SaywingPermission.dictation : [])
        return needed.filter { !permissions.isGranted($0) }
    }

    func advance() {
        let next = plan.next(after: step, granted: permissions.granted)
        guard next != step else { return }
        history.append(step)
        go(to: next, forward: true)
    }

    func back() {
        if history.isEmpty {
            let previous: SetupStep? = switch step {
            case .readingShortcuts: .readingModel
            case .dictationShortcuts: .dictationModel
            case .tryReading: .readingShortcuts
            case .tryDictation: .dictationShortcuts
            default: nil
            }
            if let previous { go(to: previous, forward: false) }
            return
        }
        while let previous = history.popLast() {
            if case let .permission(permission) = previous, permissions.isGranted(permission) { continue }
            go(to: previous, forward: false)
            return
        }
    }

    func showModel() {
        plan.wantsDictation = true
        history.append(step)
        go(to: .dictationModel, forward: false)
    }

    func chooseDictation(_ wants: Bool) {
        plan.wantsDictation = wants
        advance()
    }

    /// The only place a grant is requested: an explicit click on this step.
    func request(_ permission: SaywingPermission) {
        startWaiting(for: permission)
        permission.request { [weak self] in self?.permissions.refresh() }
    }

    func openSettings(_ permission: SaywingPermission) {
        startWaiting(for: permission)
        permission.openSettings()
    }

    func startReadingTest() {
        trial = .waiting
        model?.enqueuePrimaryShortcut()
    }

    func openDictationTest() { model?.dictation?.showWindow() }

    /// Screen Recording often applies only to a new process. The shell waits for
    /// this process to exit so the global shortcuts are free for the new one.
    func relaunch() { model?.restartSetup() }

    /// Cancels waiting, timers and helper panels; called when the window closes.
    func stop() {
        waitTask?.cancel()
        waitTask = nil
        advanceTask?.cancel()
        advanceTask = nil
        awaiting = nil
        guide.hide()
        pointer.hide()
    }

    private func go(to next: SetupStep, forward: Bool) {
        stop()
        celebrating = nil
        suggestsRelaunch = false
        movesForward = forward
        model?.setRecordingShortcut(false)
        step = next
        persistCheckpoint()
        if next == .tryReading { trial = .waiting }
        if next == .done { pointer.show() }
        AccessibilityNotification.Announcement(Self.announcement(for: next)).post()
    }

    private func startWaiting(for permission: SaywingPermission) {
        waitTask?.cancel()
        if awaiting != permission {
            AccessibilityNotification.Announcement(String(localized: "Waiting for System Settings…")).post()
        }
        awaiting = permission
        persistCheckpoint()
        suggestsRelaunch = false
        // System Settings does not tell Saywing about a change; poll only while asked.
        waitTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard self?.poll(permission) == true else { return }
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            }
        }
    }

    private func poll(_ permission: SaywingPermission) -> Bool {
        guard awaiting == permission, step == .permission(permission) else { return false }
        permissions.refresh()
        guard awaiting == permission else { return false }
        guide.follow(permission)
        return true
    }

    private func grantsChanged(_ granted: Set<SaywingPermission>) {
        guard case let .permission(permission) = step, granted.contains(permission), celebrating != permission else { return }
        waitTask?.cancel()
        waitTask = nil
        let wasWaiting = awaiting == permission
        awaiting = nil
        guide.hide()
        celebrating = permission
        AccessibilityNotification.Announcement(String(localized: "\(permission.systemName) allowed")).post()
        if wasWaiting && !NSApp.isActive { onReturn?() }
        advanceTask?.cancel()
        advanceTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
            guard let self, self.step == .permission(permission) else { return }
            self.advance()
        }
    }

    private func returnedToSaywing() {
        guard awaiting == .screenRecording else { return }
        permissions.refresh()
        if !permissions.isGranted(.screenRecording) { suggestsRelaunch = true }
    }

    private func observeReading(_ status: AppStatus, foundText: Bool?) {
        let next = trial.advanced(by: status, foundText: foundText)
        guard next != trial else { return }
        trial = next
        if next == .heard { readingConfirmed = true }
        if let message = Self.announcement(for: next) { AccessibilityNotification.Announcement(message).post() }
    }

    private static func announcement(for step: SetupStep) -> String {
        switch step {
        case .readingModel: String(localized: "Your reading voice")
        case .dictationModel: String(localized: "Dictation on your Mac")
        case .readingShortcuts, .dictationShortcuts: String(localized: "Choose your shortcuts")
        case .welcome: String(localized: "Welcome to Saywing")
        case let .permission(permission): permission.setupTitle
        case .tryReading: String(localized: "Try reading aloud")
        case .dictationOffer: String(localized: "Write with your voice too?")
        case .tryDictation: String(localized: "Try dictation")
        case .done: String(localized: "Saywing is ready")
        }
    }

    private static func announcement(for trial: ReadingTrial) -> String? {
        switch trial {
        case .heard: String(localized: "It works. Saywing is ready to read.")
        case .noText: String(localized: "No text found. Drag the frame over the whole sentence.")
        case .failed: String(localized: "Reading did not work.")
        case .waiting, .working, .speaking: nil
        }
    }
}

extension SetupPlan {
    static let dictationSteps: Set<SetupStep> = [.permission(.microphone), .permission(.accessibility), .dictationModel, .dictationShortcuts, .tryDictation]
}

/// A small floating card beside System Settings while Saywing waits for a grant,
/// so the user knows which switch to turn on. Only window bounds of System
/// Settings are read; window titles and other apps' contents are never read.
@MainActor
final class SystemSettingsGuide {
    private var panel: NSPanel?
    private var shown: SaywingPermission?
    private var dismissed: Set<SaywingPermission> = []
    private static let size = CGSize(width: 300, height: 128)
    private static let bundleID = "com.apple.systempreferences"

    func follow(_ permission: SaywingPermission) {
        guard !dismissed.contains(permission),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.bundleID,
              let settings = Self.settingsWindowFrame() else { return hide() }
        let panel = self.panel ?? makePanel()
        if shown != permission {
            panel.contentView = NSHostingView(rootView: SystemSettingsGuideView(permission: permission) { [weak self] in
                self?.dismissed.insert(permission)
                self?.hide()
            })
            shown = permission
        }
        panel.setFrameOrigin(Self.origin(beside: settings))
        guard !panel.isVisible else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        shown = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel
        return panel
    }

    /// Right of the window where there is room, otherwise left, kept on screen.
    private static func origin(beside settings: CGRect) -> CGPoint {
        let visible = (NSScreen.screens.first { $0.frame.intersects(settings) } ?? NSScreen.main)?.visibleFrame ?? settings
        var x = settings.maxX + 12
        if x + size.width > visible.maxX { x = settings.minX - size.width - 12 }
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let y = min(max(settings.maxY - size.height - 52, visible.minY + 8), visible.maxY - size.height - 8)
        return CGPoint(x: x, y: y)
    }

    private static func settingsWindowFrame() -> CGRect? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let bounds = windows
            .filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0 }
            .compactMap { ($0[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) } }
            .max { $0.width * $0.height < $1.width * $1.height }
        guard let bounds, let primary = NSScreen.screens.first else { return nil }
        // Window server coordinates start at the top left of the primary display.
        return CGRect(x: bounds.minX, y: primary.frame.maxY - bounds.maxY, width: bounds.width, height: bounds.height)
    }
}

struct SystemSettingsGuideView: View {
    let permission: SaywingPermission
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 44, height: 44)
                .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
                .help(String(localized: "Drag Saywing into the list"))
                .accessibilityLabel("Saywing app icon")
                .accessibilityAction(named: "Show Saywing in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
            VStack(alignment: .leading, spacing: 4) {
                Text("Turn on Saywing").font(.headline)
                Text("Switch on Saywing under “\(permission.systemName)”.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Missing from the list? Drag this icon in, or use + below the list.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onClose) {
                Image(systemName: "xmark").font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel("Close hint")
        }
        .padding(14)
        .frame(width: 300, height: 128, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.18)))
    }
}

/// At the end of setup, points at Saywing's menu bar item, since the app has no
/// Dock icon and would otherwise seem to disappear.
@MainActor
final class MenuBarPointer {
    private var panel: NSPanel?
    private static let size = CGSize(width: 220, height: 64)

    func show() {
        guard let item = Self.statusItemFrame() else { return }
        let panel = self.panel ?? NSPanel(contentRect: CGRect(origin: .zero, size: Self.size),
                                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: MenuBarPointerView())
        let visible = (NSScreen.screens.first { $0.frame.intersects(item) } ?? NSScreen.main)?.frame ?? item
        let x = min(max(item.midX - Self.size.width / 2, visible.minX + 8), visible.maxX - Self.size.width - 8)
        panel.setFrameOrigin(CGPoint(x: x, y: item.minY - Self.size.height - 4))
        self.panel = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 1 }
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
    }

    private static func statusItemFrame() -> CGRect? {
        NSApp.windows.first { $0.className == "NSStatusBarWindow" && $0.isVisible }?.frame
    }
}

struct MenuBarPointerView: View {
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "arrowtriangle.up.fill").font(.system(size: 12)).foregroundStyle(Color("AccentColor"))
            Text("Saywing lives here").font(.callout.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
        }
        .frame(width: 220, height: 64, alignment: .top)
        .accessibilityHidden(true)
    }
}

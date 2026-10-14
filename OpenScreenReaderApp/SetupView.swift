import AppKit
import SwiftUI

/// Guided setup: one decision per page, the primary action bottom right, Back
/// bottom left. A grant is only "allowed"; success is claimed only after a real
/// reading test played speech.
struct SetupView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var flow: SetupFlowController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size = CGSize(width: 500, height: 560)

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                page
                    .id(flow.step)
                    .transition(pageTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Color("AccentColor"))
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 1), value: flow.step)
        .accessibilityIdentifier("setup")
    }

    /// The new page arrives from the direction of travel; the old one fades in place.
    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(insertion: .move(edge: flow.movesForward ? .trailing : .leading).combined(with: .opacity),
                           removal: .opacity)
    }

    @ViewBuilder private var page: some View {
        switch flow.step {
        case .welcome: welcomePage
        case let .permission(permission): permissionPage(permission)
        case .tryReading: readingPage
        case .dictationOffer: dictationOfferPage
        case .tryDictation: dictationPage
        case .done: donePage
        }
    }

    // MARK: Pages

    private var welcomePage: some View {
        SetupPage(title: String(localized: "Welcome to Saywing"),
                  message: String(localized: "Saywing reads the text on your screen aloud and writes what you say. Everything happens on this Mac.")) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().scaledToFit().frame(width: 112, height: 112)
                .accessibilityHidden(true)
        } accessory: {
            VStack(alignment: .leading, spacing: 10) {
                Label("No account and no internet connection", systemImage: "wifi.slash")
                Label("Screenshots, text and audio are never saved", systemImage: "externaldrive.badge.xmark")
                Label("You decide each permission yourself", systemImage: "hand.raised")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func permissionPage(_ permission: SaywingPermission) -> some View {
        let granted = flow.celebrating == permission || flow.permissions.isGranted(permission)
        return SetupPage(eyebrow: permission.activity, title: permission.setupTitle, message: permission.setupMessage) {
            // Escape is a key, so it is shown as one, like the shortcut and Fn pages.
            if permission == .inputMonitoring && !granted { KeyCap("esc").accessibilityLabel("Escape key") }
            else { SetupSymbol(name: permission.setupSymbol, isComplete: granted) }
        } accessory: {
            VStack(spacing: 10) {
                if granted {
                    StatusLabel(String(localized: "Allowed"), symbol: "checkmark.circle.fill", color: .green)
                } else if flow.awaiting == permission {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for System Settings…")
                    }
                    .foregroundStyle(.secondary)
                    if permission == .screenRecording && flow.suggestsRelaunch {
                        Text("Already switched on? macOS applies it after Saywing restarts.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Quit & Reopen") { flow.relaunch() }
                            .accessibilityIdentifier("setupRelaunch")
                    }
                }
                Text("In System Settings: Privacy & Security › \(permission.systemName)")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }

    private var readingPage: some View {
        SetupPage(eyebrow: String(localized: "Read Aloud"), title: String(localized: "Try it now"),
                  message: String(localized: "Press the shortcut, then drag a frame around the sentence below.")) {
            KeyCap(flow.shortcut).accessibilityLabel("Shortcut \(flow.shortcut)")
        } accessory: {
            VStack(spacing: 14) {
                Text("Saywing reads any text on your screen aloud, right here on this Mac.")
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22).padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.6)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4])).foregroundStyle(.tertiary))
                    .accessibilityLabel("Sample sentence")
                    .accessibilityValue(Text("Saywing reads any text on your screen aloud, right here on this Mac."))
                readingStatus.frame(minHeight: 34)
            }
        }
    }

    @ViewBuilder private var readingStatus: some View {
        switch flow.trial {
        case .waiting:
            Button("Select Region") { flow.startReadingTest() }
                .disabled(!model.canChangeShortcut)
                .accessibilityIdentifier("setupReadingTest")
        case .working:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Recognizing on this Mac…") }
                .foregroundStyle(.secondary)
        case .speaking:
            Label("Reading aloud. Press Escape to stop.", systemImage: "speaker.wave.2.fill")
                .foregroundStyle(.secondary)
        case .heard:
            StatusLabel(String(localized: "It works. Saywing is ready to read."), symbol: "checkmark.circle.fill", color: .green)
        case .noText:
            VStack(spacing: 6) {
                Text("No text found. Drag the frame over the whole sentence.").foregroundStyle(.secondary)
                Button("Try Again") { flow.startReadingTest() }
            }
        case .failed:
            VStack(spacing: 6) {
                StatusLabel(model.errorMessage ?? String(localized: "Reading did not work."),
                            symbol: "exclamationmark.triangle.fill", color: .orange)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try Again") { flow.startReadingTest() }
            }
        }
    }

    private var dictationOfferPage: some View {
        SetupPage(eyebrow: String(localized: "Dictate"), title: String(localized: "Write with your voice too?"),
                  message: String(localized: "Hold Fn, speak and let go. Saywing types the text where your cursor is, recognized on this Mac.")) {
            SetupSymbol(name: "waveform.and.mic", isComplete: false)
        } accessory: {
            Text("You can also set this up later from the menu bar.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var dictationPage: some View {
        SetupPage(eyebrow: String(localized: "Dictate"), title: String(localized: "Try dictation"),
                  message: String(localized: "Click in the test field, hold Fn while you speak and release to paste.")) {
            KeyCap("fn").accessibilityLabel("Fn key")
        } accessory: {
            VStack(spacing: 14) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow { Text("Hold Fn").fontWeight(.medium); Text("Dictate, release to paste").foregroundStyle(.secondary) }
                    GridRow { Text("Press Fn twice").fontWeight(.medium); Text("Hands-free; Fn finishes").foregroundStyle(.secondary) }
                    GridRow { Text("Escape").fontWeight(.medium); Text("Discard").foregroundStyle(.secondary) }
                }
                .font(.callout)
                Button("Open Test Field…") { flow.openDictationTest() }
                    .accessibilityIdentifier("setupDictationTest")
                if let dictation = model.dictation {
                    Text(dictation.statusText).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var donePage: some View {
        let missing = flow.missingPermissions
        return SetupPage(title: missing.isEmpty ? String(localized: "You're all set") : String(localized: "Almost done"),
                         message: doneMessage(missing: missing)) {
            MenuBarIllustration()
        } accessory: {
            if !missing.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(missing) { PermissionRow(permission: $0, status: flow.permissions) }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.5)))
            }
        }
    }

    private func doneMessage(missing: [SaywingPermission]) -> String {
        let read = String(localized: "Saywing lives in the menu bar. Press \(flow.shortcut) anywhere to read a region aloud.")
        guard flow.wantsDictation, !missing.contains(.microphone) else { return read }
        return read + " " + String(localized: "Hold Fn to dictate.")
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if flow.canGoBack {
                Button("Back") { flow.back() }
                    .accessibilityIdentifier("setupBack")
            }
            Spacer()
            actions
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    @ViewBuilder private var actions: some View {
        switch flow.step {
        case .welcome:
            primary(String(localized: "Continue")) { flow.advance() }
        case let .permission(permission):
            if flow.celebrating == permission || flow.permissions.isGranted(permission) {
                primary(String(localized: "Continue")) { flow.advance() }
            } else {
                Button("Later") { flow.advance() }.accessibilityIdentifier("setupLater")
                if flow.awaiting == permission {
                    primary(String(localized: "Open System Settings")) { flow.openSettings(permission) }
                } else {
                    primary(String(localized: "Allow…")) { flow.request(permission) }
                        .accessibilityIdentifier("allow-\(permission.rawValue)")
                }
            }
        case .tryReading:
            if flow.readingConfirmed {
                primary(String(localized: "Continue")) { flow.advance() }
            } else {
                Button("Skip") { flow.advance() }.accessibilityIdentifier("setupSkip")
            }
        case .dictationOffer:
            Button("Not Now") { flow.chooseDictation(false) }
            primary(String(localized: "Set Up Dictation")) { flow.chooseDictation(true) }
        case .tryDictation:
            primary(String(localized: "Continue")) { flow.advance() }
        case .done:
            primary(String(localized: "Done")) { model.finishSetup() }
                .accessibilityIdentifier("setupDone")
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
    }
}

/// Shared page layout: hero, small activity label, title, one explanatory sentence.
private struct SetupPage<Hero: View, Accessory: View>: View {
    var eyebrow: String?
    let title: String
    let message: String
    @ViewBuilder var hero: Hero
    @ViewBuilder var accessory: Accessory
    /// The pressed button disappears with the old page; VoiceOver continues at the new title.
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        // Hero and title keep the same place on every page; only what follows varies.
        VStack(spacing: 0) {
            hero.frame(height: 112).padding(.top, 52)
            Spacer().frame(height: 22)
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.semibold)).tracking(0.8)
                    .foregroundStyle(Color("AccentColor"))
                    .padding(.bottom, 6)
            }
            Text(title)
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
                .onAppear { titleFocused = true }
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
                .padding(.top, 8)
            accessory.padding(.top, 22)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// The step's symbol on a tinted disc; on success a checkmark draws itself, in
/// the same language as the reading control's end states.
private struct SetupSymbol: View {
    let name: String
    let isComplete: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .fill((isComplete ? Color.green : Color("AccentColor")).opacity(0.14))
                .frame(width: 104, height: 104)
            if isComplete {
                CheckmarkShape()
                    .trim(from: 0, to: progress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    .frame(width: 44, height: 36)
                    .onAppear {
                        guard !reduceMotion else { progress = 1; return }
                        withAnimation(.easeOut(duration: 0.35)) { progress = 1 }
                    }
            } else {
                Image(systemName: name)
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(Color("AccentColor"))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

private struct KeyCap: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.system(size: 34, weight: .medium, design: .rounded))
            .padding(.horizontal, 22).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.background))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.12), radius: 0, x: 0, y: 3)
    }
}

/// A slice of the menu bar with Saywing's item highlighted, for where to find it later.
private struct MenuBarIllustration: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Image("SaywingMenuBar")
                .renderingMode(.template).resizable().scaledToFit()
                .frame(width: 22, height: 22)
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color("AccentColor").opacity(0.22)))
            Text(Date.now, format: .dateTime.hour().minute())
        }
        .font(.system(size: 15))
        .foregroundStyle(.primary)
        .padding(.horizontal, 18).padding(.vertical, 8)
        .background(Capsule().fill(.quaternary.opacity(0.7)))
        .accessibilityHidden(true)
    }
}

/// Colour stays on the symbol; the words keep full text contrast.
private struct StatusLabel: View {
    let text: String
    let symbol: String
    let color: Color
    init(_ text: String, symbol: String, color: Color) {
        self.text = text
        self.symbol = symbol
        self.color = color
    }

    var body: some View {
        Label { Text(text).fontWeight(.medium) } icon: { Image(systemName: symbol).foregroundStyle(color) }
    }
}


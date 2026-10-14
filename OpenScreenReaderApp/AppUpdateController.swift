import AppKit
import Combine
import OpenScreenReaderCore
import Sparkle
import SwiftUI

@MainActor
final class AppUpdateController: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    @Published private(set) var isConfigured = false
    @Published private(set) var canCheck = false
    @Published private(set) var updateAvailable = false
    @Published private(set) var installationPending = false
    @Published private(set) var automaticallyChecks = false
    private var controller: SPUStandardUpdaterController?
    private var observations: Set<AnyCancellable> = []
    private let relaunchGate = UpdateRelaunchGate()
    private let isBusy: () -> Bool

    init(bundle: Bundle = .main, disabled: Bool = false, isBusy: @escaping () -> Bool) {
        self.isBusy = isBusy
        super.init()
        guard !disabled, UpdateConfiguration(
            feed: bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "",
            publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "") != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        // Never send the optional system profile, even if an old preference enabled it.
        controller.updater.sendsSystemProfile = false
        controller.updater.automaticallyDownloadsUpdates = false
        controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] in self?.canCheck = $0 }.store(in: &observations)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] in self?.automaticallyChecks = $0 }.store(in: &observations)
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.cancelPendingInstallation() }.store(in: &observations)
        do {
            try controller.updater.start()
            isConfigured = true
        } catch {
            // A misconfigured updater must never prevent local reading or dictation.
            self.controller = nil
            observations.removeAll()
            canCheck = false
        }
    }

    func checkForUpdates() {
        guard !isBusy(), isConfigured else { return }
        controller?.checkForUpdates(nil)
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func installWhenIdle() {
        guard !isBusy() else { return }
        installationPending = false
        relaunchGate.resumeIfIdle(true)
    }

    private func cancelPendingInstallation() {
        relaunchGate.cancel()
        installationPending = false
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if isBusy() {
            throw NSError(domain: "Saywing.Updates", code: 1, userInfo: [NSLocalizedDescriptionKey:
                String(localized: "Finish reading or dictation before updating.")])
        }
    }

    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool { false }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        let postponed = relaunchGate.postponeIfBusy(isBusy(), install: installHandler)
        installationPending = postponed
        return postponed
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { cancelPendingInstallation() }

    var supportsGentleScheduledUpdateReminders: Bool { true }
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool { !isBusy() }
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) { updateAvailable = true }
    func standardUserDriverWillFinishUpdateSession() { updateAvailable = false }
}

struct AppUpdateMenu: View {
    @ObservedObject var updates: AppUpdateController
    let busy: Bool
    var body: some View {
        if updates.installationPending {
            Button("Install Update and Restart…") { updates.installWhenIdle() }.disabled(busy)
        } else {
            Button(updates.updateAvailable ? String(localized: "Update Available…") : String(localized: "Check for Updates…")) {
                updates.checkForUpdates()
            }.disabled(busy || !updates.isConfigured || (!updates.canCheck && !updates.updateAvailable))
        }
    }
}

struct AppUpdateSettings: View {
    @ObservedObject var updates: AppUpdateController
    let busy: Bool
    var body: some View {
        Section {
            Toggle("Automatically check for updates", isOn: Binding(
                get: { updates.automaticallyChecks }, set: { updates.setAutomaticallyChecks($0) }))
                .toggleStyle(.checkbox).disabled(!updates.isConfigured)
            AppUpdateMenu(updates: updates, busy: busy)
            if !updates.isConfigured { Text("Updates are not configured in this build.").foregroundStyle(.secondary) }
            if updates.installationPending { Text("Finish reading or dictation before updating.").foregroundStyle(.secondary) }
        } header: {
            Text("Updates")
        } footer: {
            Text("Update checks contact the download server. Screenshots, text and recordings stay on your Mac. Updates install only when you choose.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var permissionNotice: String?

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Status", value: model.status.title)
                LabeledContent("Global shortcut", value: HotkeyShortcut.readScreenRegion.displayName)
                LabeledContent("Speech model", value: "Not packaged yet")
            }

            Section("Privacy") {
                Text("Only the selected region is captured in memory. Images are discarded after the capture check. Nothing is copied to the clipboard or sent over the network. OCR and speech are not available yet.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Permissions") {
                Text("Screen Recording allows the selected region to be captured. Input Monitoring lets Escape cancel while another app is active; only Escape is checked, and monitoring stops when the operation ends.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Allow Screen Recording…") {
                    let granted = CGRequestScreenCaptureAccess()
                    permissionNotice = granted ? "Screen Recording is allowed. Select a region to retry."
                        : "Enable OpenScreenReader under System Settings → Privacy & Security → Screen & System Audio Recording, then reopen the app if requested."
                }
                Button("Allow Input Monitoring…") {
                    let granted = CGRequestListenEventAccess()
                    permissionNotice = granted ? "Input Monitoring is allowed. Select a region to retry."
                        : "Enable OpenScreenReader under System Settings → Privacy & Security → Input Monitoring, then reopen the app if requested."
                }
                if let permissionNotice {
                    Text(permissionNotice).fixedSize(horizontal: false, vertical: true)
                }
                if let errorMessage = model.errorMessage {
                    Text(errorMessage).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
        .navigationTitle("OpenScreenReader Settings")
        .accessibilityLabel("OpenScreenReader settings")
    }
}

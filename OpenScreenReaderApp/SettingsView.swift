import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Status", value: "Ready")
                LabeledContent("Global shortcut", value: HotkeyShortcut.readScreenRegion.displayName)
                LabeledContent("Speech model", value: "Not packaged yet")
            }

            Section("Privacy") {
                Text("Screen recognition and speech will run locally. This foundation build does not capture the screen or access the network.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
        .navigationTitle("OpenScreenReader Settings")
        .accessibilityLabel("OpenScreenReader settings")
    }
}

import SwiftUI

@main
struct SpeechFixtureApp: App {
    var body: some Scene {
        WindowGroup("OpenScreenReader Speech Test") {
            Text("Hallo Welt. Dieser Text wird auf diesem Mac vorgelesen. Mit Escape lässt sich die Wiedergabe jederzeit stoppen.")
                .font(.system(size: 32))
                .foregroundStyle(.black)
                .padding(40)
                .frame(width: 720, height: 300)
                .background(.white)
                .accessibilityIdentifier("speechFixtureText")
        }
        .windowResizability(.contentSize)
    }
}

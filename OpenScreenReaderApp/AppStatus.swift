enum AppStatus: String, CaseIterable, Equatable, Sendable {
    case ready
    case selecting
    case capturing
    case recognizing
    case speaking
    case stopped
    case error

    var title: String {
        switch self {
        case .ready:
            "Ready"
        case .selecting:
            "Selecting"
        case .capturing:
            "Capturing"
        case .recognizing:
            "Recognizing"
        case .speaking:
            "Speaking"
        case .stopped:
            "Stopped"
        case .error:
            "Error"
        }
    }

    var symbolName: String {
        switch self {
        case .ready, .stopped:
            "waveform"
        case .selecting:
            "viewfinder"
        case .capturing:
            "camera.viewfinder"
        case .recognizing:
            "text.viewfinder"
        case .speaking:
            "speaker.wave.2"
        case .error:
            "exclamationmark.triangle"
        }
    }
}

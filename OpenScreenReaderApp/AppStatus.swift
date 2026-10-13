enum AppStatus: String, CaseIterable, Equatable, Sendable {
    case ready
    case selecting
    case capturing
    case recognizing
    case synthesizing
    case speaking
    case waiting
    case stopped
    case error

    var title: String {
        switch self {
        case .ready:
            String(localized: "Ready")
        case .selecting:
            String(localized: "Selecting")
        case .capturing:
            String(localized: "Capturing")
        case .recognizing:
            String(localized: "Recognizing")
        case .speaking:
            String(localized: "Speaking")
        case .waiting:
            String(localized: "Waiting for next text")
        case .synthesizing:
            String(localized: "Preparing voice")
        case .stopped:
            String(localized: "Stopped")
        case .error:
            String(localized: "Error")
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
        case .waiting:
            "text.badge.plus"
        case .synthesizing:
            "waveform.badge.magnifyingglass"
        case .error:
            "exclamationmark.triangle"
        }
    }
}

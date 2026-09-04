import Foundation
import NaturalLanguage

/// Optional controls for explicitly requested local listening comparisons.
/// Existing app requests still use Serena and per-segment language detection.
struct SpeechWorkerRequest: Decodable {
    enum Voice: String, Decodable { case serena = "Serena", ryan = "Ryan", aiden = "Aiden" }
    enum Language: String, Decodable { case german = "German", english = "English", auto }

    let text: String
    let voice: Voice?
    let language: Language?
    let seed: UInt64?

    var selectedVoice: String { (voice ?? .serena).rawValue }

    func resolvedLanguage(for segment: String) -> String {
        if let language { return language.rawValue }
        let detected = NLLanguageRecognizer.dominantLanguage(for: segment)
        return detected == .german ? "German" : detected == .english ? "English" : "auto"
    }
}

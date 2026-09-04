import Foundation

@main
struct SpeechRequestChecks {
    static func main() throws {
        func decode(_ json: String) throws -> SpeechWorkerRequest {
            try JSONDecoder().decode(SpeechWorkerRequest.self, from: Data(json.utf8))
        }
        let original = try decode(#"{"text":"Hallo Welt."}"#)
        precondition(original.selectedVoice == "Serena")
        precondition(original.resolvedLanguage(for: "Das ist ein deutscher Beispielsatz.") == "German")
        precondition(original.seed == nil)
        for voice in ["Serena", "Ryan", "Aiden"] {
            let request = try decode("{\"text\":\"42\",\"voice\":\"\(voice)\",\"language\":\"German\",\"seed\":42}")
            precondition(request.selectedVoice == voice)
            precondition(request.resolvedLanguage(for: "42") == "German")
            precondition(request.seed == 42)
        }
        for field in [#""voice":"not-a-voice""#, #""language":"not-a-language""#, #""seed":-1"#] {
            do {
                _ = try decode("{\"text\":\"Test\",\(field)}")
                fatalError("Invalid comparison option accepted")
            } catch is DecodingError { }
        }
        print("PASS: original defaults, three voices, explicit German, seed, and invalid options")
    }
}

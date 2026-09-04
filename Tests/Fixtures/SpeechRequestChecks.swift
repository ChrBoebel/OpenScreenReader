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
        precondition(original.selectedTemperature == 0.9)
        let lower = try decode(#"{"text":"Test","temperature":0.5}"#)
        precondition(lower.selectedTemperature == 0.5)
        for voice in ["Serena", "Ryan", "Aiden"] {
            let request = try decode("{\"text\":\"42\",\"voice\":\"\(voice)\",\"language\":\"German\",\"seed\":42}")
            precondition(request.selectedVoice == voice)
            precondition(request.resolvedLanguage(for: "42") == "German")
            precondition(request.seed == 42)
        }
        for field in [#""voice":"not-a-voice""#, #""language":"not-a-language""#, #""seed":-1"#,
                      #""temperature":-0.1"#, #""temperature":1.1"#, #""temperature":"NaN""#] {
            do {
                _ = try decode("{\"text\":\"Test\",\(field)}")
                fatalError("Invalid comparison option accepted")
            } catch is DecodingError { }
        }
        print("PASS: original defaults, three voices, explicit German, seed, lower temperature, and invalid options")
    }
}

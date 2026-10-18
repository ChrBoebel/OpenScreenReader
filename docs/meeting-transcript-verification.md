# Meeting-Mitschrift — Prüfprotokoll

Stand 2026-10-16, Branch `codex/meeting-transcript` (von `main` ff68998). Auftrag des Eigentümers: Wispr Flows Meeting-Aufnahme analysieren, einen Vorschlag machen, dann „okey baue es“. Entscheidung: [ADR 0006](decisions/0006-local-meeting-transcript.md).

## Ausgangslage

**Wispr Flow 1.6.1147 (statisch analysiert, unter anderem mit REA 6.5.0):**
- Mikrofon und Systemaudio laufen als getrennte Spuren. Systemaudio kommt ab macOS 14.4 über einen Core-Audio-Prozess-Tap, davor über ScreenCaptureKit.
- Beide Spuren werden lokal zwischengespeichert, als Opus kodiert und an Wisprs Server gestreamt. Dort transkribieren Soniox, ein eigenes Modell oder OpenAI.
- Weitere Bausteine:
  - ein Echo-Gate per Kreuzkorrelation;
  - Meeting-Erkennung über die Prozesse, die das Mikrofon halten;
  - Sprechernamen über die Bedienungshilfen von Zoom und Teams;
  - ein automatischer Einwilligungshinweis im Meeting-Chat.

**Messung auf dem Mac des Eigentümers (macOS 26.6.2):**
- Apples `SpeechTranscriber` ist verfügbar; `de_DE`, `de_AT` und `de_CH` sind installiert.
- 53,8 s deutsches Testaudio wurden in 0,5–0,9 s erkannt, also 60- bis 110-mal schneller als Echtzeit. Satzzeichen und Zahlen stimmen; Fachwörter werden falsch erkannt („Saywing“ → „Siving“).
- Live mit `.fastResults` liegt der Text ≤ ~1 s hinter dem Audio.
- Apple Foundation Models können Deutsch, sind aber nicht verfügbar, weil Apple Intelligence aus ist.

## Umsetzung

Zehn Commits, Übersicht in [Architektur](architecture.md#lokale-meeting-mitschrift--2026-10-15). Kein Netzwerkzugriff, keine Modellgewichte, kein fremder Code. Core-Audio-Tap, Speech und Accelerate sind Systemschnittstellen; Apples Beispielcode diente nur als Vorlage für die Schritte.

| Entscheidung | Grund |
|---|---|
| Apples `SpeechTranscriber` statt Whisper-Worker | Gebaut für lange Live-Audios, außerhalb unseres Prozesses, keine Gewichte, blockiert das Diktieren nicht |
| Nur installierte Sprachen, `AssetInventory.reserve` ohne Download | Keine neue Netzwerkverbindung. Ohne Reservierung warnte das Framework: „Cannot use modules with unallocated locales … will be an error in a future release“ |
| Zeitstempel in ganzen Samples der Analyzer-Rate | Mit Sekunden als Gleitkommazahl lehnte der echte Analyzer Eingaben ab („Audio input timestamp overlaps or precedes prior audio input“), danach hing Stopp |
| Stopp mit Frist; Analyzer ohne Eingang wird abgebrochen | Ein Analyzer, der nie Audio bekam (Systemaudio fehlt), finalisierte nie; im Diagnoseprogramm nachgestellt |
| Aggregate-Device nur mit dem Tap | Wie Apples Beispiel; ein Headset als Ausgabegerät brächte sonst eigene Eingangsströme vor den Tap |
| Echo pro Wort statt pro Segment | Der echte Erkenner legte Echo und meinen Satz nach 1 s Pause in *ein* Segment (0–10 s); das Ausblenden ganzer Segmente löschte meinen Satz mit |
| Echo-Spannen nur über den Ton der anderen | Fenster-plus-Nachlauf deckte zuvor die nächsten 4 s ab |
| Ring im Menüleistensymbol vor allen anderen Zuständen | Die Aufnahme hört andere Apps; die Mikrofonanzeige von macOS reicht dafür nicht |
| Keine neuen Einstellungs-Schlüssel, keine Fenster-Autosave | Datenschutz-Zusage „keine neuen Schlüssel“ |

## Ausgeführte Prüfungen

- **Meeting-Suites** (`MeetingTranscriptTests`, `MeetingTimelineTests`, `EchoGateTests`, `MeetingAudioTests`, `MeetingRouterTests`, `AppleMeetingRecognizerTests`, `MeetingControllerTests`, `MeetingAppTests`): **44/44 bestanden**.
- **Echte Erkennung im Test**, nicht gemockt, auf diesem Mac:
  - `germanSpeechLandsOnTheMeetingTimeline`: Deutsche Sprache (`say -v Anna`) wird erkannt, die Ergebnisse liegen ab der eingespeisten Zeit 100 s; 1,2 s Laufzeit.
  - `speakerEchoDisappearsFromMeWhileMyOwnSentenceStays`: Echte Erkennung, echtes Echo-Gate und echte Weiche. „Andere“ sagen einen Satz, das Mikrofon hört ein Echo (90 ms, Faktor 0,3) und danach einen eigenen Satz mit zweiter Stimme. Bei „Ich“ bleiben „Danke“ und „Freitag“, während „Woche“ und „Tests“ verschwinden.
  - Ein erster Lauf dieses Tests bestand zu Unrecht, weil `say` kein Float-AIFF schreibt. Der Test verlangt die Audiodatei jetzt ausdrücklich.
- **Echo-Gate mit echter Sprachausgabe** (Diagnoseprogramm): Korrelation 0,89–0,99 bei 90 ms Verzögerung, durchgehend erkannt; die Spanne endet mit dem Satz der anderen (5,1 s + Nachhall).
- **Gesamtsuite** `OpenScreenReaderAppTests` nach dem letzten Code-Commit: **235 Tests in 23 Suites bestanden**, 0 fehlgeschlagen (`** TEST SUCCEEDED **`). 2 XCTest wurden übersprungen, weil dem Test-Host die Freigaben für Bildschirmaufnahme und Eingabeüberwachung fehlen (unverändert gegenüber vorher). Ein früherer Lauf vor den letzten Korrekturen ergab 233/233.
- **Release-Build** (arm64): **BUILD SUCCEEDED**, keine Warnungen in den neuen Dateien. Ein erster Release-Build zeigte veraltete `vDSP.DFT`- und Sendable-Warnungen; behoben.
- `scripts/check-localization.py`: bestanden. Alle neuen Texte sind auf Deutsch übersetzt, ebenso `NSAudioCaptureUsageDescription`.
- **Sichtprüfung:** Das Fenster wurde hell und dunkel in allen Zuständen gerendert (opt-in `MeetingPreviewTests`). Dabei fiel auf, dass der Freigabe-Hinweis im fertigen Transkript stehen blieb; behoben und mit Test abgesichert.

## Design-Review 2026-10-16

Prüfung nach dem [Apple-Design-Skill](https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md) und dem [Saywing-Markensystem](brand-identity/BRAND_SYSTEM.md), anhand gerenderter Fensterzustände (hell/dunkel) und des Menüleistensymbols.

| Befund | Grundsatz | Umsetzung |
|---|---|---|
| Hauptaktionen in Systemblau statt Petrol | Marke | `.tint(AccentColor)` wie Einrichtung und Einstellungen; Pale Petrol im Dunkelmodus |
| Einwilligung als linksbündige Liste mit Leerfläche | Vertrautheit, Einfachheit | Seitenmuster der Einrichtung: Symbol auf getönter Kreisfläche, Titel, ein Satz, dann die drei Punkte und der Chat-Hinweis |
| Pegel als graue Fortschrittsbalken, nur 1× pro Sekunde | Reaktion, Marke | Fünf Kapsel-Balken in Petrol, 5 Hz, kritisch gedämpft; Stille sichtbar als Punkte |
| Gelbes Hinweisband | Marke, Farbe nur am Symbol | Abgerundete, zurückhaltende Fläche, orangefarbenes Warnsymbol, Text in voller Kontrastfarbe |
| Vier gleichrangige Tasten im fertigen Zustand | Gruppierung, Hierarchie | Verlassen links, Behalten rechts, „Sichern …“ als einzige Hauptaktion |
| Kopieren/Sichern ohne Rückmeldung | Rückmeldung bei Abschluss | Häkchen „Kopiert“/„Gesichert“ in der Taste, ohne Breitenänderung |
| Verwerfen löscht ungesicherten Text ohne Rückfrage | Handlungsfreiheit, Nachsicht | Bestätigung nur bei ungesichertem Text (destruktive Taste); sonst sofort |
| Stopp per Return | Sicherheit | ⌘. wie in macOS üblich |
| Mitlaufen zieht beim Nachlesen weg | Handlungsfreiheit, Orientierung | Mitlaufen nur am unteren Rand; „Neueste“ bringt zurück |
| Harte Zustandswechsel | Bewegung | Kritisch gedämpfte Überblendung (0,35 s), neue Beiträge blenden ein; reduzierte Bewegung: kurze bzw. keine Überblendung |
| Fußleiste der Seite „Nicht verfügbar“ eingerückt | Handwerk | Gleiche 24-pt-Kante wie alle Seiten |
| Ring im Menüleistensymbol | Form statt Farbe | Geprüft: passt zu Punkt und Dreieck, eindeutig unterscheidbar (hell/dunkel) |

Nach dem Review: Gesamtsuite **236 Tests in 23 Suites bestanden** (neu: Rückfrage beim Verwerfen ungesicherten Textes), Release-Build ohne Warnungen, Lokalisierungsprüfung bestanden, alle Zustände erneut hell/dunkel gerendert und angesehen.

Unverändert und bewusst: rotes Aufnahmesymbol und Dauer im Fenster (siehe [UX-Anforderungen](ux-requirements.md#design-review-meeting-mitschrift--2026-10-16)), Systemschrift, keine Ansagen von VoiceOver während der Aufnahme (sie würden über die Lautsprecher mit aufgenommen; die Liste bleibt mit VoiceOver lesbar). In einzelnen Offscreen-Renderings erscheinen hervorgehobene Tasten grau, weil das Vorschaufenster nicht aktiv ist; in den übrigen sind sie Petrol bzw. Pale Petrol.

## Nicht geprüft / offen

- **Systemaudio-Tap auf echter Hardware:** Er wurde nicht ausgeführt. Der erste Start löst eine Freigabe-Abfrage von macOS aus, die am Gerät bestätigt werden muss. Ungeprüft sind damit die Abfrage selbst, das Ausschließen von Saywing, das tatsächliche Tap-Format und das Verhalten bei verweigerter Freigabe. Die App zeigt nach 20 s ohne Signal einen Hinweis, auch dieser ist nicht live erprobt.
- **Echter Call** über Lautsprecher und über Kopfhörer: Wortfehler auf echter Sprache, Echo-Doppelungen, Schwellen des Echo-Gates (Startwerte), CPU, Speicher und Akku über 60 min.
- **Mikrofon-Engine parallel zum Diktieren:** Zwei `AVAudioEngine` am selben Mikrofon sind unter macOS üblich, hier aber nicht live geprüft.
- **Dateisystem-Nachweis:** Ein Test, dass während einer echten Sitzung keine Datei geschrieben wird, fehlt noch. Der Code schreibt nur im Sichern-Dialog.
- **Bekannte Grenzen:**
  - eine Sprache pro Mitschrift;
  - Fachwörter, weil Apples Kontext-Wortliste in der Messung keine Wirkung hatte;
  - Doppelreden über Lautsprecher kann eigene Wörter ausblenden;
  - keine Sprechernamen, keine Zusammenfassung;
  - erst ab macOS 26.
- **Rechtliche Prüfung** (§ 201 StGB, DSGVO) vor einer Veröffentlichung.

## So prüft der Eigentümer am Gerät

1. Den Build starten, dann Menü → **Meeting mitschreiben …** → **Alle sind informiert – starten**. macOS fragt nach Systemaudio; erlauben.
2. In einem Browser ein Video mit Sprache abspielen und dabei selbst sprechen: „Andere“ und „Ich“ müssen getrennt erscheinen, das Menüleistensymbol zeigt einen Ring.
3. Dasselbe über Lautsprecher: Der Videoton darf bei „Ich“ nicht doppelt auftauchen.
4. **Stopp** → **Kopieren** / **Sichern …** / **Verwerfen** ausprobieren.
5. Zum Gegentest die Freigabe in den Systemeinstellungen entziehen: Nach 20 s muss der Hinweis erscheinen.

## Lokale Installation 2026-10-16

Der Branch wurde vor dem PR auf `main` 5b489db aufgesetzt; danach bestand die Gesamtsuite mit **239 Tests in 24 Suites**. Installiert wurde ein Release-Build mit den geprüften Modellen und Laufzeiten der bisherigen App (`bundle-dictation-runtime.py --speech-from … --with-qwen --whisper-large-model … --development-only`). Die bisherige App liegt als Rückfallkopie unter `.build/previous-before-meeting/Saywing.app`.

Dabei fielen zwei Punkte auf, die nicht von der Mitschrift kommen:

- **Sprach-Worker:** Die installierte App trug noch den Supertonic-Worker ohne die Intel-Thread-Begrenzung aus `main`. Der Worker der Entwicklungs-Laufzeit wurde mit `scripts/update-supertonic-worker.rb` aktualisiert. Für die Laufzeitquelle wurde in einer Kopie der bisherigen App nur `worker.py` und dessen Hash im Beleg nach derselben Regel ersetzt; auf Apple Silicon ist das Verhalten unverändert. `package-development-app.rb` war nicht nutzbar, weil sich der Interpreter der Entwicklungs-Laufzeit geändert hat (`Runtime receipt mismatch: venv/bin/python`).
- **Signatur mit Sparkle:** Der Release-Build läuft mit Hardened Runtime. Ad hoc signiert verweigert dyld das eingebettete `Sparkle.framework` („mapping process and mapped file (non-platform) have different Team IDs“): Die App stürzte beim Start ab, auch nachdem Sparkle ad hoc nachsigniert war. Der lokale Build ist deshalb wie die Debug-Konfiguration signiert: ad hoc, mit `Saywing.entitlements`, ohne Hardened Runtime. `codesign --verify --deep --strict` und `verify-app-permissions.py` bestanden. Saywing startete und lief stabil; der Diktier-Worker lud das gewählte Modell selbst. Der dokumentierte Entwicklungsweg (`bundle-dictation-runtime.py` auf einem Release-Build) erzeugt seit der Sparkle-Integration also eine nicht startfähige App. Das sollte getrennt im Skript behoben werden.

Die Systemaudio-Freigabe, die Mikrofonfreigabe für die neue Signatur und ein echter Call bleiben die Prüfung am Gerät (siehe oben).

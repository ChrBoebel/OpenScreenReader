# Proposed architecture

> Diese Architektur ist eine begründete Ausgangshypothese. Die Prozessgrenzen und Packaging-Strategie werden durch technische Spikes validiert, bevor der vollständige MVP entsteht.

Aktueller Entwicklungsstand: Nach der Hörentscheidung des Eigentümers vom 2026-09-05 ist Supertonic 3 das Standardmodell, zunächst mit M1. Ein lokaler Python-/ONNX-Prozess ist über dieselbe `SpeechReading`-Schnittstelle an OCR und AVAudioEngine angeschlossen; siehe [Supertonic-Integration](research/supertonic-integration.md). Der bisherige Swift-/MLX-Qwen-Spike bleibt als Vergleich erhalten, wird von der App aber weder gestartet noch als Fallback verwendet. Dies legt die portable Produktions-Runtime und Release-Verpackung noch nicht fest.

## Systemübersicht

### Everyday controls update — 2026-09-09

`SpeechReading.setPaused` pauses the native player without discarding scheduled buffers. `SpeechAudioPlayer` suppresses both prebuffer auto-start and short-tail start while paused; its bounded producer/drain waits remain cancellable. `AppModel.isPaused` is orthogonal to the core speaking phase, so adding regions remains available. The app-level speech watchdog is suspended during a user pause; worker packet watchdogs still cover actual inference, excluding channel backpressure. Resume restores the watchdog; Stop/skip clear pause state.

Queue rows have stable UUIDs. Removal/reordering refreshes only the next prepared text; play-now moves the selected row to the head and uses the existing generation-protected skip/handoff. A transient `NSPopover` hosts `PlaybackControlsView` only after a capsule-button click. Its previews are presentation-only and remain session-local; the closed capsule gets only status/count/level and a callback. `SetupView` offers explicit permission requests and read-only preflight, not a fabricated end-to-end result. Since 2026-10-14 it is a paged flow: `SetupPlan` derives the next step from live grants only, `ReadingTrial` maps the real pipeline status to the in-window reading test (success only after speech played), and `SetupFlowController` owns cancellable grant polling, a stale-protected auto-advance and the `SystemSettingsGuide`/`MenuBarPointer` panels. `AppModel` owns the window and flow and tears both down on close. `ScreenCaptureService` excepts only visible own windows with the `readableBySaywing` identifier from its own-app exclusion. An injected `missingReadingPermission` check opens setup before a selection that could only fail. After a failure, `AppModel.errorHelp` (`retry`, `shortcut`, `allow(permission)`) drives `ReadingErrorView` in the capsule's popover instead of opening setup. `DictationCapsulePlacement` anchors the dictation capsule below `InsertionTarget.caretRect()` and otherwise uses the reading control's `ReadingPanelPlacement`. `DictationController` takes the shared `InterfaceSoundPlaying` and derives result cues from the capsule presentation; the microphone cues (`listening`, `handsFree`, `captured`) are played at the recording's own events, the closing one only after `DictationRecording.finish()`. `DictationRecording` abstracts `MicrophoneRecorder` so tests can drive a recording without a microphone. `MenuBarIcon` composes cached template glyphs from `AppModel.menuBarIndicator`.

`SpeechTextNormalizer` repairs explicit soft hyphens and non-breaking spaces without rewriting ordinary hyphens, numbers or codes. The Python segmenter preserves abbreviation/initial/ordinal context, honors explicit paragraph boundaries and retains the existing 240-character cap. This is deterministic segmentation, not an LLM text rewrite or a proof of audible linguistic fidelity.

`LocalSpeechService.installedConfiguration` selects bundled Speech resources when present, otherwise the explicit development installation. Bundled Python is under `SupertonicRuntime/python/bin/python3`; its standard library and pinned package closure are private build resources. The offline `package-development-app.rb` spike verifies model/installed-runtime hashes before copying, excludes unrelated base-interpreter packages and build-time pkgconfig links, checks symlink containment, ad-hoc signs nested native code and the app, and retains licenses. It is intentionally not a release/signing/notarization pipeline.

```text
GlobalHotkeyManager
        │
        ▼
SelectionOverlay ──► ScreenCaptureService
                            │
                            ▼
                      VisionOCRService
                            │
                            ▼
                 TextNormalizer / Segmenter
                            │
                            ▼
                         TTSService
                      ┌─────┴─────┐
                      ▼           ▼
               QwenProvider  SupertonicProvider
                      │
                      ▼
                 AudioPlayback
```

## Native macOS-App

Geplanter Stack:

- SwiftUI für Einstellungen und Menüleistenoberfläche;
- AppKit für globale Fenster, Auswahl-Overlay und Ereignisbehandlung;
- ScreenCaptureKit oder CoreGraphics für die Bereichserfassung;
- Vision mit `VNRecognizeTextRequest` für lokale OCR;
- AVFoundation für Audiopuffer und Wiedergabe.

### Vorgeschlagene Module

- `AppShell`: Lebenszyklus, Menüleiste und Einstellungen;
- `GlobalHotkeyManager`: registriert Lesen/Hinzufügen und verhindert Konflikte; vollständiger Stop bleibt bei Esc und expliziten Stop-Controls;
- `SelectionOverlay`: Multi-Monitor-Auswahl und Abbruch;
- `ScreenCaptureService`: erfasst ausschließlich das gewählte Rechteck;
- `VisionOCRService`: OCR, Sprache und Lesereihenfolge;
- `TextPipeline`: Normalisierung, Segmentierung und Treuemodus;
- `TTSService`: modellunabhängige Auftrags- und Abbruchsteuerung;
- `AudioPlaybackController`: gepufferte Wiedergabe mit sofortigem Stop;
- `ModelManager`: Manifest- und Hashprüfung des gebündelten Modells, Version und Speicherpolitik;
- `PrivacyAudit`: zentraler Ort für optionale Netzwerk- und Dateisystemereignisse.

### Implementiertes Status-Panel

Update 2026-09-22: Zwei native `ReadingInlineButton`-Ziele ersetzen bei Hover die Welle innerhalb der 136-pt-Kapsel: Pause/Fortsetzen und Optionen. `controlsBlend` überblendet ohne Layoutänderung. Eigene Responder-Mausereignisse unterscheiden Klick von Drag ab 5 pt, ohne blockierende Tracking-Schleife. Ein schwach referenziertes Popover hält die Tasten sichtbar; Menü/Accessibility-Öffnung zeigt den Anker synchron. `present`, Retract und Hide schützen vor veralteten Klicks; beim Hide wird der Popover-Delegate vor dem Schließen gelöst, damit er den Zeichen-Takt nicht neu startet. Menüeintrag und Accessibility-Aktionen bleiben ohne Hover erreichbar. `dockEdge` bestimmt die nach innen gerichtete Popover-Seite; seitliche Glyphen bleiben aufrecht. Pipeline, Provider, Audio und Speicherung ändern sich nicht. Die folgenden früheren Esc-Layer-Angaben sind dadurch überholt.

`ReadingPanelPlacement` berechnet die Position relativ zum `visibleFrame` des gewählten Displays. Unten bleibt die Zeichenfläche 300 × 92 pt, seitlich ist sie 92 × 300 pt: Layoutkoordinaten werden abgebildet, Text/Symbole/Taste nicht gedreht. Der Controller verarbeitet Drag-Callbacks von der dekorativen Statusfläche, getrennt vom Stop-Button; ab 5 pt folgt das Fenster direkt, auf Loslassen wird der nächste erlaubte Rand samt normiertem Versatz gespeichert. Die 220-ms-Einrast-Task ist abbrechbar und generationsgeschützt; Reduce Motion positioniert unmittelbar. Anzeigeänderungen begrenzen die Geometrie erneut. Die Settings-Vorschau ist ein expliziter reiner Präsentationszustand `positioning`, keine simulierte Pipeline. Ein neuer Auftrag räumt sie über denselben `hide()`-Pfad auf.

Die App-Shell injiziert `ReadingPanelController` über `ReadingStatusPresenting` in `AppModel`. Der Controller erhält einen geschlossenen Statuswert, die ausgewählte Display-ID, einen auf die aktuelle Pipeline-Generation begrenzten Stop-Callback und während der Wiedergabe einen flüchtigen skalaren Pegel. Screenshot, OCR-Text, Audio und technische Fehlerpayloads verlassen diese Grenze nicht.

Das Vorlese-Control (`ReadingControlView`) ist ein layer-basierter nativer `NSView` auf einer festen 300 × 92 pt großen Zeichenfläche; die sichtbare Kapsel ist 44 pt hoch und zwischen 44 pt (Punkt) und rund 250 pt (Hinweistext) breit, der Rest ist Platz für den gezeichneten Schatten. Die Kapsel ist ein Container mit `NSVisualEffectView` (Material `hudWindow`, hinter dem Fenster), einer sehr dunklen Tönung, Tiefen- und Glanzverlauf, Randlicht, einem radialen Leuchten, neun `CAShapeLayer`-Balken mit eigenem Leuchten, einem Wander-Licht für die Erkennung, einem Symbol-Layer, einem Bloom-Ring und zwei bei Hover eingeblendeten sekundären Tasten. Ein `NSTextField` zeigt nur bei Hinweisen kurz Text; die Stop-Taste ist ein echter 44-pt-`NSButton`. `ReadingStatusPresenting.show` erhält für den ersten sichtbaren Zustand zusätzlich das Auswahlrechteck in Bildschirmpunkten; `SelectionFlightWindow` (klick-durchlässig, nur auf dem gewählten Display) lässt einen Mint-Geist des Rahmens per Core-Animation-Pfadmorph in den Landepunkt fallen. Erst danach erscheint das Panel, gleichzeitig spielt der Controller den Öffnungsklang; `hide()` bricht den Flug sofort ab. Zustandswechsel werden zusätzlich als VoiceOver-Ansage gepostet. Es gibt kein Auto Layout und keinen SwiftUI-Host; alle Frames werden pro Bild von Hand gesetzt, sodass keine Constraint-Schleife entstehen kann. Ein `CADisplayLink` aus `NSView.displayLink(target:selector:)` treibt eine von Hand integrierte Feder (Öffnen mit Überschwingen, Schließen kritisch gedämpft) sowie die Zustandsüberblendungen; sein Ziel ist ein schwach referenzierender Proxy, damit der View freigegeben werden kann. Bei ruhenden Endzuständen pausiert der Link. Die Stop-Taste spielt beim Drücken über den Controller einen Tap-Klang und löst `NSHapticFeedbackManager` aus; dieser Pfad ist von der Pipeline entkoppelt und wird durch die Abbruchbereinigung nicht abgeschnitten. `PlaybackEnvelope` berechnet außerhalb des Audiothreads 20-ms-Pegelfenster aus dem vorhandenen PCM. `AppModel` fragt den zur gerenderten Sampleposition gehörenden Pegel alle 33 ms ab; Auftragsschutz und Ressourcenabbau beenden diesen Takt. Provider ohne Pegelunterstützung liefern über `SpeechReading` den Standardwert null.

`AppModel` blendet das Panel vor Auswahl/Aufnahme aus und veröffentlicht sichtbare Arbeitszustände erst nach der Aufnahme. Der vorhandene ScreenCaptureKit-Filter schließt zusätzlich die eigene App aus. Das `NSPanel` ist nicht aktivierend, wird nie Key/Main Window und bleibt beim Wechsel in andere Apps sichtbar. Eigene Generationen und abgebrochene Timer verhindern, dass ein veralteter Button oder eine alte Ausblendung einen neuen Auftrag beeinflusst. Bildschirmänderungen positionieren es neu oder blenden es aus, wenn sein Display fehlt. [Verifikation und Grenzen](reading-panel-verification.md).

## TTS-Prozess

### Geschwindigkeit und Textwarteschlange

`SpeechReading.playbackRate` ist eine providerunabhängige, live änderbare Eigenschaft. `SpeechAudioPlayer` verbindet Player → `AVAudioUnitTimePitch` → Mixer; Rate wird auf 0,75–2 begrenzt, Pitch bleibt 0 Cent. Modellparameter und Gewichte bleiben unverändert. Der Vorpuffer entspricht mindestens einer Sekunde bei der aktuellen Startgeschwindigkeit. Die feste Kapazität beträgt acht Sekunden Quell-PCM (44.100 Hz Mono-Float32: rund 1,35 MiB), damit bei 2× bis zu vier Sekunden Vorlauf für die nächste Satzsynthese bleiben. Die Grenze schrumpft beim Live-Verlangsamen nicht unter bereits geplante Puffer. [Apple API](https://developer.apple.com/documentation/avfaudio/avaudiounittimepitch).

`AppModel` verwaltet höchstens fünf zusätzliche OCR-Ergebnisse im RAM. Seit der Eigentümerentscheidung vom 2026-09-09 führt der primäre Carbon-Hotkey über `enqueuePrimaryShortcut` zum vorhandenen `addToQueue`-Pfad: im Leerlauf neue Auswahl, während Sprache/Vorbereitung zusätzliche Auswahl/Aufnahme/OCR. Bei bereits laufender Auswahl/Aufnahme/OCR oder voller Warteschlange bleibt die Sitzung bestehen und eine Meldung erklärt den Zustand. Eine zweite Carbon-Tastenkombination bleibt lediglich als optionaler kompatibler Alias erhalten. Der explizite Menü-Stop nutzt weiterhin `enqueueReadRequest` und ist vom Hotkey getrennt. Die bestehende Auswahloberfläche wird wiederverwendet; das Statuspanel bleibt während Auswahl/Aufnahme verborgen und kehrt danach ohne Öffnungsklang zurück. Eine UUID verwirft veraltete Zusatz-Ergebnisse; ein separater Timeout begrenzt Aufnahme/OCR. Ein leerer, zu langer oder fehlgeschlagener Zusatz wird mit Statusmeldung abgelehnt, ohne laufende Sprache oder bereits wartende Texte zu stoppen.

Der Core-Coordinator besitzt weiterhin nur den aktuellen Sprachauftrag. Beim FIFO-Wechsel wird dieser abgeschlossen, eine neue Generation erzeugt und das schon erkannte Ergebnis über dieselbe Synthese-/Wiedergabelogik gestartet. Die Sitzungsgeneration des Escape-Monitors bleibt über diesen Wechsel stabil, wird aber bei Gesamtstopp/neuem manuellen Start invalidiert. Wenn nur eine noch laufende Zusatz-Auswahl/OCR übrig ist, bleibt der alte Kontext als abbrechbarer Eigentümer bestehen; `waiting` ist ein Präsentationszustand, keine neue Core-Phase. „Next Text“ beendet nur den aktuellen Sprachauftrag und startet den nächsten fertigen Eintrag; Gesamtstopp und Fehler räumen beide Task-Pfade und die gesamte Textliste auf. Es wird kein zusätzlicher Sprachworker vorab gestartet.

Seit 2026-09-09 verwendet die Warteschlange einen einzelnen Python-/ONNX-Prozess pro Sitzung. `SpeechReading.prepareNext` bereitet höchstens einen Nachfolger vor, `stopCurrent` bewahrt ihn beim normalen Übergang/Überspringen, `stop` verwirft sämtliche Jobs und beendet den Prozess. Andere Provider dürfen über die Default-Implementierungen weiterhin ohne Vorbereitung arbeiten. `AppModel` aktualisiert die Vorbereitung erst nach Beginn der aktuellen Wiedergabe bzw. beim Hinzufügen während Sprache; beim Dequeue wird der vorhandene Nachfolger nicht vor seiner Übernahme ersetzt.

`SpeechWorkerSession` führt ausschließlich einen Syntheseauftrag gleichzeitig aus. Das neue explizite `--session`-Protokoll versieht ready/audio/end mit Version 2 und der UUID des Textauftrags; abweichende IDs/Versionen werden abgelehnt. Modell und Stimme werden einmal geladen/verifiziert, der Zufallsseed wird pro Text zurückgesetzt. Der Legacy-Einzelauftrag ohne Flag bleibt für frühere Entwicklungs-Apps kompatibel. Nach dem end-Paket des aktuellen Texts darf derselbe Worker den Nachfolger synthetisieren, während der Player die restlichen Puffer abspielt. Es gibt kein paralleles zweites Modell und keine Vorabsynthese der gesamten Liste.

Pro Job begrenzt `SpeechPreparationBuffer` die RAM-Pakete auf acht Quell-Sekunden und blockiert den Produzenten bei voller Kapazität. Aktueller Transportbuffer, nächster Transportbuffer und Player ergeben zusammen höchstens 24 Quell-Sekunden geplantes/gepuffertes PCM (rund 4,04 MiB), zuzüglich begrenzter In-flight-Pakete, Transportkodierung und Engine-/Modellspeicher. Beide wartenden Seiten werden bei Abbruch geweckt. Eine vorbereitete Übernahme pausiert abbrechbar 120 ms. Stop räumt beide Jobs, Reader, Timer, Audio und Prozess auf. Wird eine noch nicht fertig synthetisierte aktuelle Passage übersprungen, wird deren Worker hart beendet und der wartende Nachfolger mit einem neuen Worker gestartet. Bereits laufende Vorbereitung nach abgeschlossener aktueller Synthese bleibt beim Überspringen erhalten.

Die App beendet die Sitzung bei Gesamtstopp, Fehler oder leerer Warteschlange. Ein separater generationsgeschützter 30-s-Leerlauftimer begrenzt Warmhalten ohne aktiven/vorbereiteten Auftrag, etwa beim Warten auf eine zusätzliche Auswahl. Packet-Watchdogs (90 s bis Audio, danach 30 s ohne Workerpaket) laufen nicht während regulärer Buffer-Backpressure. Vor jedem Prozessstart sowie nach jedem asynchronen Übergang werden Cancellation und Jobidentität geprüft.

Text und PCM laufen über anonyme Pipes, die Wiedergabe erfolgt im App-Prozess. Der Worker darf weder Netzwerkverbindungen aufbauen noch Dateien schreiben (ausgenommen `/dev/null`). Python läuft isoliert und ohne Bytecode-Schreibzugriffe. `scripts/update-supertonic-worker.rb` aktualisiert explizit nur den projekt-eigenen Worker samt Receipt-Hash, verweigert lokale Abweichungen und lädt weder Modelle noch Pakete nach. [Messungen und Grenzen](warm-queue-verification.md).

Weitergehendes Warmhalten über abgeschlossene Sitzungen hinweg bleibt eine noch nicht implementierte Vergleichsoption. Eine mögliche Variante hätte folgende Eigenschaften:

- App startet den Worker kontrolliert;
- Modell wird einmal geladen und zeitlich begrenzt warm gehalten;
- Kommunikation über eine lokale, nicht nach außen gebundene Schnittstelle;
- Audio wird blockweise übertragen;
- jeder Auftrag erhält eine ID und ein Cancellation-Signal;
- Prozessende löscht temporäre Zustände.

Vor dem MVP müssen zwei Varianten verglichen werden:

1. portabel gebündelter Python-/ONNX-Worker;
2. native ONNX-Integration; der vorherige MLX-Pfad bleibt ein Vergleich.

Bewertungskriterien: Startzeit, Signierung/Notarisierung, Paketgröße, Fehlertoleranz, Energieverbrauch, Lizenzkette und Wartbarkeit.

## Modellbereitstellung im offiziellen MVP

Das Standardmodell soll Bestandteil des signierten Release-Artefakts sein, damit nach der App-Installation keine separate Modellauswahl oder Laufzeit-Downloadstrecke nötig ist. Bevor diese Strategie verbindlich wird, muss ein Packaging-Spike nachweisen, dass App, Worker, Runtime und Modell gemeinsam signiert, notarisiert und auf einem sauberen Mac offline gestartet werden können.

- Modellgewichte werden nicht in Git eingecheckt.
- Release-Builds verwenden ein allowlist-basiertes Manifest mit unveränderlichen Revisionen und SHA-256-Hashes.
- Modell, Tokenizer, Konvertierung, Runtime, Stimmen und transitive Abhängigkeiten benötigen eine dokumentierte Lizenzfreigabe.
- Der MVP lädt zur Laufzeit keine Modelle, Pakete oder Updates aus dem Netzwerk.
- Die Provider-Abstraktion bleibt erhalten, damit spätere Plattformen und lokale Modelle nicht an ein MLX-Artefakt gekoppelt sind.

## Provider-Abstraktion

`TTSProvider` soll mindestens unterstützen:

- `load()` und `unload()`;
- Fähigkeiten und Sprachen abfragen;
- Streaming-Synthese starten;
- Auftrag abbrechen;
- Modell- und Lizenzmetadaten melden;
- Gesundheitsstatus prüfen.

Primär:

- Supertonic 3, vom Eigentümer nach direktem Hörvergleich ausgewählt; M1, acht Schritte, normale Synthesegeschwindigkeit. Satzweise Synthese, begrenzte Audio-Pakete und acht Sekunden Quell-PCM im Wiedergabepuffer; Live-Tempo 0,75–2×.

Vergleich, nicht automatisch verwendet:

- Qwen3-TTS 0.6B 4-bit Swift/MLX. Der Eigentümer empfand die untersuchten Stimmen als zu wechselhaft.

Die Supertonic-OpenRAIL-M-Bedingungen, das angekündigte Ende des offiziellen Supports sowie die vollständige Python-/ONNX-Lizenz- und Packaging-Kette müssen vor Distribution geprüft werden.

Nicht für den ersten Pfad:

- Chatterbox wegen Startlatenz und Speicherbedarf;
- Thorsten/Piper bis Runtime und Phonemizer-Lizenzkette praktisch festgelegt sind.

## Nebenläufigkeit und Abbruch

- Ein neuer Sprachauftrag erhält eine Generation-ID; ein wiederholter Hotkey zum Hinzufügen widerruft nicht die noch sprechende Generation.
- Ergebnisse älterer Generationen werden verworfen.
- `Esc` beendet Overlay, OCR-Task, TTS-Task, Audioqueue und aktiven Workerauftrag.
- Nur der aktuelle Auftrag darf Audiopuffer an die Wiedergabe senden.
- Fehler eines TTS-Providers dürfen die Menüleisten-App nicht beenden.

## Datenschutzgrenze

Der Standardpfad darf Screenshot, OCR-Text und generiertes Audio nicht dauerhaft speichern. Diagnoseexporte sind opt-in, zeigen vor dem Schreiben exakt ihren Inhalt und entfernen Bildschirmdaten standardmäßig.

## Offene technische Spikes

1. Minimaler Multi-Monitor-Auswahlrahmen mit ScreenCaptureKit.
2. OCR-Lesereihenfolge für Fließtext und zwei Spalten.
3. Native Swift/MLX-Integration: erste Audioblöcke und Abbruch lokal bestanden; Warmstart, Speicherbedarf und Langläufe noch offen.
4. Code Signing und Notarisierung eines Worker-Bundles.
5. Netzwerkfreiheit der vollständig installierten Release-App nachweisen.
6. Energie- und RAM-Warmhaltepolitik bestimmen.

## Lokales Diktieren — 2026-10-13

`DictationController` ist neben dem Vorlese-Coordinator eingebunden, mit eigener Swift-6-MainActor-Zustandssteuerung, Mikrofon-RAM-Buffer, Zielvalidierung, kurzlebiger Clipboard-Transaktion und einem `DictationTranscribing`-Provider. `DictationWorker` betreibt das explizit ausgewählte ASR-Modell über isolierte anonyme Pipes; Supertonic bleibt TTS. `AppModel` serialisiert den Vorlesen→Diktieren-Wechsel, beendet vor Mikrofonstart die Sprachwiedergabe und verwirft Diktieren synchron vor einem Vorlesestart. Prozesssession und Aufnahme-ID verhindern verspätete Ergebnisse. Kaltstart speichert Audio maximal 60 s im RAM; Inferenz und Modellstart haben Zeitlimits. Der Worker wird beim App-Start automatisch vorbereitet und bleibt im Leerlauf sowie beim Vorlesen verfügbar. Nur aktive Diktierinferenz wird beim Wechsel zum Vorlesen beendet; der nächste Diktierstart lädt bei Bedarf automatisch nach. Ruhezustand, inaktive Benutzersitzung und Beenden entladen den Worker. Nach Aufwachen und aktiver Sitzung wird er automatisch wieder vorbereitet. Wiederholte Ladeanforderungen sind idempotent; Beenden sperrt verspätete Warmstarts. Kein Mikrofonstart durch diese Vorbereitung. Das Bundle enthält die gepinnte ASR-Laufzeit unter `Contents/Resources/Dictation`; fehlende Ressourcen führen zu einer sichtbaren Fehlermeldung. [Manifest, Protokoll, Packaging und Grenzen](research/qwen-dictation-runtime.md).

## Auswahl des Diktiermodells — 2026-10-13

Auf Wunsch des Eigentümers stehen Qwen3-ASR und Whisper Turbo als explizite lokale
Modelle zur Auswahl. Die Auswahl wird unter `dictationModel.v1` gespeichert und
beim Start sowie nach Ruhezustand wiederhergestellt. Wechsel sind während eines
Diktats gesperrt; im Leerlauf wird der vorherige Worker beendet und seine verspäteten
Callbacks werden verworfen. Das gewählte Modell lädt automatisch ohne Mikrofonstart.
Fehlende oder beschädigte Modelle erzeugen einen Fehler, keinen automatischen
Fallback oder Download. Beide verwenden die bestehende Offline-Sandbox und dieselbe
flüchtige Audio-/Clipboard-Pipeline. Quelle, Revision, Größe, Prüfsumme und Lizenz:
[Whisper Turbo](research/whisper-turbo-dictation.md).

Seit 2026-10-14 steht zusätzlich Whisper Large v3 (8-bit, `whisper-large-v3`) zur
Auswahl. Es nutzt dieselbe mlx-whisper-Laufzeit wie Whisper Turbo, ist genauer
angelegt, aber langsamer; nur das gewählte Modell wird geladen. [Quelle, Revision,
Prüfsumme und Lizenz](research/whisper-large-v3-dictation.md).

### Modelle bei Bedarf installieren — 2026-10-14

Builds bündeln standardmäßig nur Whisper Turbo; es ist das Standardmodell. Qwen3-ASR
und Whisper Large v3 erscheinen in der Modellauswahl als „… installieren (Größe)“.
`DictationModelStore` kennt mitgelieferte (`Contents/Resources/Dictation/<Ordner>`)
und installierte Modelle (`~/Library/Application Support/Saywing/DictationModels/<Ordner>`).
Nach Bestätigung lädt `URLSessionModelFetcher` die im gebündelten Manifest gepinnten
Dateien (ephemere Session, nur HTTPS zu Hugging Face, auch bei Weiterleitungen) in
einen Staging-Ordner. Größe und SHA-256 jeder Datei werden geprüft, erst dann wird
der Ordner atomar an seinen Platz verschoben. Abbruch und Fehler entfernen das
Staging; ein neuer Installationsversuch verwirft Ergebnisse eines abgebrochenen.
Nach erfolgreicher Installation wird das Modell ausgewählt und geladen.
`DictationWorker` übergibt dann `--model-root`; `worker.py` liest das Manifest weiter
aus dem Bundle und prüft die Hashes beim Laden erneut. Eine gespeicherte Auswahl
eines nicht installierten Modells bleibt erhalten, gestartet wird aber Whisper Turbo.
`bundle-dictation-runtime.py` bündelt Qwen nur mit `--with-qwen` und Large v3 nur mit
`--whisper-large-model`.

## Standardmodell und Vokabular — 2026-10-14

Nach Entscheidung des Eigentümers ist Whisper Turbo das Standardmodell, wenn noch
keine Wahl gespeichert ist; Qwen3-ASR bleibt auswählbar. Jede Anfrage an den Worker
trägt optional `vocabulary` (≤ 50 Begriffe, je ≤ 60 Zeichen, ohne Steuerzeichen;
sonst Fehler `processing_failed`). Whisper erhält die Begriffe als `initial_prompt`
(„A, B, C.“), gekürzt auf das Token-Budget des Prompts, Qwen3-ASR als `hotwords`.
Ergibt die Erkennung eine Wiederholungsschleife oder nur die Begriffsliste, dekodiert
derselbe Worker dieselbe Aufnahme einmal ohne Vokabular. Das ist kein Wechsel des
Modells oder Providers. [Messung und Grenzen](dictation-vocabulary-verification.md).

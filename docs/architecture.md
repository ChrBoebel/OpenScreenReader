# Proposed architecture

> Diese Architektur ist eine begründete Ausgangshypothese. Die Prozessgrenzen und Packaging-Strategie werden durch technische Spikes validiert, bevor der vollständige MVP entsteht.

Aktueller Entwicklungsstand: Nach der Hörentscheidung des Eigentümers vom 2026-09-05 ist Supertonic 3 das Standardmodell, zunächst mit M1. Ein lokaler Python-/ONNX-Prozess ist über dieselbe `SpeechReading`-Schnittstelle an OCR und AVAudioEngine angeschlossen; siehe [Supertonic-Integration](research/supertonic-integration.md). Der bisherige Swift-/MLX-Qwen-Spike bleibt als Vergleich erhalten, wird von der App aber weder gestartet noch als Fallback verwendet. Dies legt die portable Produktions-Runtime und Release-Verpackung noch nicht fest.

## Systemübersicht

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
- `GlobalHotkeyManager`: registriert Start/Stop und verhindert Konflikte;
- `SelectionOverlay`: Multi-Monitor-Auswahl und Abbruch;
- `ScreenCaptureService`: erfasst ausschließlich das gewählte Rechteck;
- `VisionOCRService`: OCR, Sprache und Lesereihenfolge;
- `TextPipeline`: Normalisierung, Segmentierung und Treuemodus;
- `TTSService`: modellunabhängige Auftrags- und Abbruchsteuerung;
- `AudioPlaybackController`: gepufferte Wiedergabe mit sofortigem Stop;
- `ModelManager`: Manifest- und Hashprüfung des gebündelten Modells, Version und Speicherpolitik;
- `PrivacyAudit`: zentraler Ort für optionale Netzwerk- und Dateisystemereignisse.

## TTS-Prozess

Der aktuelle Entwicklungsspike verwendet einen einzelnen Python-/ONNX-Prozess pro Vorleseauftrag. `SpeechReading` trennt die Auftragssteuerung vom konkreten `LocalSpeechService`; `SpeechRuntimeConfiguration` legt den expliziten Supertonic-Pfad und 44,1 kHz fest. Text und PCM laufen über anonyme Pipes, die Wiedergabe erfolgt im App-Prozess. Der Worker darf im Entwicklungsprofil weder Netzwerkverbindungen aufbauen noch Dateien schreiben (ausgenommen `/dev/null`). Python läuft isoliert und ohne Bytecode-Schreibzugriffe. Abbruch stoppt zuerst den Audioplayer und beendet anschließend den eigenen Worker; Generationen verwerfen verspätete Ergebnisse. Das Modell bleibt zwischen Textsegmenten geladen, aber nicht zwischen Aufträgen. Dieses Verhalten ist implementiert und kein Nachweis für den warmen Latenzzielwert.

Ein langlebiger Worker bleibt eine noch nicht implementierte Vergleichsoption. Eine mögliche Warmhaltevariante hätte folgende Eigenschaften:

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

- Supertonic 3, vom Eigentümer nach direktem Hörvergleich ausgewählt; M1, acht Schritte, normale Geschwindigkeit. Satzweise Synthese, begrenzte Audio-Pakete und vier Sekunden Wiedergabepuffer.

Vergleich, nicht automatisch verwendet:

- Qwen3-TTS 0.6B 4-bit Swift/MLX. Der Eigentümer empfand die untersuchten Stimmen als zu wechselhaft.

Die Supertonic-OpenRAIL-M-Bedingungen, das angekündigte Ende des offiziellen Supports sowie die vollständige Python-/ONNX-Lizenz- und Packaging-Kette müssen vor Distribution geprüft werden.

Nicht für den ersten Pfad:

- Chatterbox wegen Startlatenz und Speicherbedarf;
- Thorsten/Piper bis Runtime und Phonemizer-Lizenzkette praktisch festgelegt sind.

## Nebenläufigkeit und Abbruch

- Jeder neue Hotkey-Aufruf erhöht eine Generation-ID.
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

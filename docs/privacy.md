# Privacy principles and requirements

## Grundsatz

OpenScreenReader verarbeitet möglicherweise hochsensible Bildschirmdaten. Datenschutz ist deshalb keine Marketingoption, sondern eine technische Invariante.

## Verbindliche Standardwerte

- Der offizielle MVP enthält sein Standardmodell; OCR und TTS laufen nach der Installation vollständig lokal.
- Kein Konto und keine Anmeldung.
- Keine Telemetrie im offiziellen Build.
- Keine Cloud-Synchronisation.
- Kein automatisches Schreiben in die Zwischenablage.
- Keine dauerhafte Speicherung von Screenshots, OCR-Text oder Audio.
- Keine stillen Netzwerk-Fallbacks, wenn ein lokales Modell fehlschlägt.
- Berechtigungen werden erst angefragt, wenn die dazugehörige Funktion verwendet wird.

## Netzwerkzugriffe

Der MVP-Runtimepfad darf keine Netzwerkverbindung benötigen oder selbstständig aufbauen. Das Standardmodell wird mit dem signierten Release-Artefakt von der Projektwebsite ausgeliefert. Vor dem Website-Download werden mindestens angezeigt:

- Modellname und Version;
- Quelle;
- erwartete Größe;
- Lizenz;
- installierte Größe und Systemanforderungen;
- Integritätsprüfung beziehungsweise SHA-256-Hash.

Updateprüfungen sind später nur transparent und abschaltbar zulässig. Eine fehlende Verbindung darf den lokalen Betrieb nicht blockieren.

## Speicher- und Lebenszyklus

- Die gewählte Tastenkombination (Taste und Modifikatoren) wird lokal unter `readingShortcut.v1` in UserDefaults gespeichert. Die Auswahl erfasst keine Tastatureingaben und enthält keine Bildschirm-, OCR- oder Audioinhalte.
- Screenshots bleiben im Prozessspeicher und werden nach OCR freigegeben.
- OCR-Text bleibt nur so lange erhalten, wie Auftrag und Wiedergabe laufen.
- Audiopuffer werden nach Wiedergabe oder Abbruch verworfen.
- Gebündelte Modell- und Runtime-Dateien sind dauerhafte Programmbestandteile, enthalten aber keine nutzerspezifischen Bildschirm- oder Sprachinhalte.
- Absturzberichte dürfen keine Screenshots, OCR-Texte oder Audioinhalte enthalten.
- Diagnoseexporte sind opt-in und zeigen vor dem Schreiben eine Vorschau.

## macOS-Berechtigungen

- Bildschirmaufnahme ist für die Bereichserfassung erforderlich und muss verständlich begründet werden.
- Accessibility beziehungsweise Input Monitoring wird nur angefragt, wenn der gewählte globale Hotkey oder die Abbruchsteuerung es technisch benötigt.
- Die App darf keine weitergehenden Berechtigungen aus Bequemlichkeit anfordern.

## Überprüfbarkeit

Der aktuelle Entwicklungspfad überträgt OCR-Text über eine anonyme Pipe an den lokalen Qwen-Worker, nicht als Kommandozeilenargument oder Datei. PCM wird im Speicher abgespielt. Ein zusätzliches Entwicklungsprofil verweigert dem Worker Netzwerkzugriffe und Dateischreibzugriffe außer auf `/dev/null`; echte Synthese unter diesem Profil sowie verweigerte Verbindungs- und Schreibversuche wurden geprüft. Wiedergabe- und Abbruchtests prüfen außerdem, dass die Zwischenablage unverändert bleibt. Dies ersetzt nicht die noch offene Prüfung des vollständig gebündelten Release-Artefakts. Details und Grenzen: [Runtime-Evaluation](research/swift-runtime-evaluation.md).

Das Repository soll dokumentieren, wie Nutzer die Datenschutzversprechen selbst prüfen können:

1. Offline-Funktionstest unmittelbar nach Installation des vollständigen Release-Artefakts;
2. Netzwerkbeobachtung während OCR und TTS;
3. Kontrolle temporärer Dateien;
4. Kontrolle der Zwischenablage;
5. reproduzierbare beziehungsweise nachvollziehbare Release-Builds;
6. vollständige Third-Party- und Modell-Lizenzübersicht.

## Produktkommunikation

Zulässige Aussagen sind beispielsweise:

- „No text or screenshots are uploaded.“
- „Works offline after installation.“
- „No account required.“
- „No telemetry in the official build.“

Nicht verwendet werden sollen absolute, nicht beweisbare Aussagen wie „100 % sicher“.

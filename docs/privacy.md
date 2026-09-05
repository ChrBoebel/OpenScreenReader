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
- Für Interface-Klänge werden nur Ein/Aus unter `interfaceSoundsEnabled.v1` und die Lautstärke unter `interfaceSoundsVolume.v1` lokal gespeichert. Die fünf festen Stereo-Hinweisklänge (Öffnen, Abschluss, Hinweis, Taste gedrückt, Taste losgelassen, teils in zwei Voicings) werden beim Start mathematisch im Speicher erzeugt; sie verwenden keine Aufnahme, keinen OCR-Text, kein Sprachmodell und keine Netzwerkverbindung. Ihre wiederverwendbaren Puffer enthalten nur diese festen Töne, keine Nutzerinhalte; es werden keine Audiodateien geschrieben. Die haptische Rückmeldung der Stop-Taste nutzt nur die System-API ohne Daten.
- Das Flug-Fenster nach der Aufnahme zeichnet nur die Geometrie des Auswahlrechtecks als Mint-Kontur, nie den Bildinhalt; es ist klick-durchlässig und wird nach der Landung geschlossen.
- Die Stimmbalken erhalten nur einen flüchtigen Pegelwert, keinen Audiopuffer. Dieser wird aus 20-ms-Fenstern des ohnehin abgespielten lokalen PCM berechnet und folgt der Wiedergabeposition, nicht dem Eingang neuer Synthesepakete. Vergangene Pegelfenster werden verworfen; die vorhandene maximal viersekündige Audio-Warteschlange begrenzt den Vorlauf. Abbruch setzt Warteschlange und Anzeige zurück. Keine Pegel-Historie, kein Audio-Tap und keine zusätzliche Berechtigung.
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

Der aktuelle Entwicklungspfad überträgt OCR-Text über eine anonyme Pipe an den lokalen Supertonic-Worker, nicht als Kommandozeilenargument oder Datei. PCM wird im Speicher abgespielt. Ein zusätzliches Entwicklungsprofil verweigert dem Worker Netzwerkzugriffe und Dateischreibzugriffe außer auf `/dev/null`; Python läuft ohne Bytecode-Schreibzugriffe und ohne benutzerspezifische Importpfade. Die installierten Modelle und Abhängigkeiten werden ausschließlich im expliziten Entwicklungsschritt bereitgestellt, niemals durch die App nachgeladen. Wiedergabe- und Abbruchtests prüfen außerdem, dass die Zwischenablage unverändert bleibt. Dies ersetzt nicht die noch offene Prüfung des vollständig gebündelten Release-Artefakts. Tatsächliche Prüfergebnisse und Grenzen: [Supertonic-Integration](research/supertonic-integration.md); vorherige Qwen-Messungen bleiben in der [Runtime-Evaluation](research/swift-runtime-evaluation.md) dokumentiert.

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

# Privacy principles and requirements

## Grundsatz

Saywing (bisher OpenScreenReader) verarbeitet möglicherweise hochsensible Bildschirmdaten. Datenschutz ist deshalb keine Marketingoption, sondern eine technische Invariante. Die Umbenennung ändert diese Vorgaben nicht; der separate Diktierprototyp ist noch nicht Bestandteil des hier beschriebenen Vorlesepfads.

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

- Die neue explizit geöffnete Wiedergabeansicht darf bis zu 100 Zeichen je wartendem Text anzeigen. Die geschlossene Kapsel bleibt textfrei. Einträge werden über flüchtige UUIDs bearbeitet; Entfernen/Umsortieren ersetzt gegebenenfalls auch das vorbereitete Audio. Stop leert weiterhin alles und schließt die Ansicht. Pause hält nur die vorhandenen begrenzten RAM-Puffer und die aktive Sitzung, ohne Dateien zu schreiben. Einrichtung speichert ausschließlich `setupDismissed.v1`, niemals ein angeblich bestandenes Berechtigungsergebnis.
- Ein privates Packaging-Experiment darf das vorhandene Modell und die gepinnte Runtime als Programmbestandteile in `Contents/Resources/Speech` tragen. Kein Runtime-Download und kein Fallback auf die Entwicklerinstallation, wenn dieser Bundle-Ordner existiert, aber beschädigt ist. Redistribution, vollständige Lizenzkette und eine Prüfung auf einem frischen Mac bleiben Release-Gates.

- Vorlesegeschwindigkeit wird als Zahl unter `speechPlaybackRate.v1` gespeichert; der separate Hinzufügen-Shortcut als Taste/Modifikatoren unter `enqueueShortcut.v1`. Keine Audio-, Text- oder Bildschirmdaten werden dadurch gespeichert. Bis zu fünf wartende OCR-Texte mit je maximal 8.000 Zeichen/48.000 UTF-8-Bytes bleiben nur im RAM. Sie werden nach FIFO-Wiedergabe freigegeben; Gesamtstopp, Fehler oder Beenden leeren die Liste und verwerfen verspätete Aufnahme-/OCR-Ergebnisse. Die Liste enthält Text, Auswahlgeometrie und Zählwerte, niemals Screenshots. Der Sprachservice darf ausschließlich für ihren nächsten Eintrag Audio vorab im RAM erzeugen; keine Vorab-TTS der gesamten Liste. Genau ein Worker bleibt innerhalb der Sitzung geladen und bearbeitet Texte seriell. Aktueller und nächster Transportbuffer sowie Player sind auf je acht Sekunden Quell-Audio begrenzt (zusammen rund 4,04 MiB), unabhängig vom Tempo. Dies begrenzt die Swift-PCM-Warteschlangen, nicht In-flight-Pakete, Transportkodierung oder den Gesamtspeicher von Audio-Engine und Modellworker. Stop/Esc/Beenden löschen beide Transportbuffer und die Audioqueue und beenden den warmen Worker. Ohne aktive/vorbereitete Arbeit endet Warmhalten spätestens nach 30 s. Keine neue Datei-Historie, Telemetrie oder Runtime-Netzwerkverbindung.
- Für die Panelposition werden nur `readingPanelEdge` (unten/links/rechts) und `readingPanelOffset` (normierter Versatz 0–1) lokal in UserDefaults gespeichert. Keine Display-ID, absoluten Bildschirmkoordinaten oder Bewegungsaufzeichnungen. Ziehen nutzt nur normale Mausereignisse der eigenen Statusfläche und benötigt keine zusätzliche Berechtigung; die Positionsvorschau startet weder Aufnahme noch OCR oder Sprache.
- Die gewählte Tastenkombination (Taste und Modifikatoren) wird lokal unter `readingShortcut.v1` in UserDefaults gespeichert. Die Auswahl erfasst keine Tastatureingaben und enthält keine Bildschirm-, OCR- oder Audioinhalte.
- Für Interface-Klänge werden nur Ein/Aus unter `interfaceSoundsEnabled.v1` und die Lautstärke unter `interfaceSoundsVolume.v1` lokal gespeichert. Die fünf festen Stereo-Hinweisklänge (Öffnen, Abschluss, Hinweis, Taste gedrückt, Taste losgelassen, teils in zwei Voicings) werden beim Start mathematisch im Speicher erzeugt; sie verwenden keine Aufnahme, keinen OCR-Text, kein Sprachmodell und keine Netzwerkverbindung. Ihre wiederverwendbaren Puffer enthalten nur diese festen Töne, keine Nutzerinhalte; es werden keine Audiodateien geschrieben. Die haptische Rückmeldung der Stop-Taste nutzt nur die System-API ohne Daten.
- Das Flug-Fenster nach der Aufnahme zeichnet nur die Geometrie des Auswahlrechtecks als Mint-Kontur, nie den Bildinhalt; es ist klick-durchlässig und wird nach der Landung geschlossen.
- Die Stimmbalken erhalten nur einen flüchtigen Pegelwert, keinen Audiopuffer. Dieser wird aus 20-ms-Fenstern des ohnehin abgespielten lokalen PCM berechnet und folgt der Wiedergabeposition, nicht dem Eingang neuer Synthesepakete. Vergangene Pegelfenster werden verworfen; die maximal achtsekündige Quell-Audio-Warteschlange begrenzt den Vorlauf. Abbruch setzt Warteschlange und Anzeige zurück. Keine Pegel-Historie, kein Audio-Tap und keine zusätzliche Berechtigung.
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

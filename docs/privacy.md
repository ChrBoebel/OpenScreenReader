# Privacy principles and requirements

## Grundsatz

Saywing (bisher OpenScreenReader) verarbeitet möglicherweise hochsensible Bildschirmdaten. Datenschutz ist deshalb keine Marketingoption, sondern eine technische Invariante. Die Umbenennung ändert diese Vorgaben nicht. Seit der Eigentümerentscheidung vom 2026-10-13 ist lokales Diktieren als eigener Ablauf integriert; nur für dessen ausdrücklich gestartetes Einfügen gilt die unten beschriebene Zwischenablage-Ausnahme.

## Verbindliche Standardwerte

- Der offizielle MVP enthält sein Standardmodell; OCR und TTS laufen nach der Installation vollständig lokal.
- Kein Konto und keine Anmeldung.
- Keine Telemetrie im offiziellen Build.
- Keine Cloud-Synchronisation.
- Kein automatisches Schreiben in die Zwischenablage beim Vorlesen. Diktieren darf für eine ausdrücklich gestartete Aufnahme über Cmd+V einfügen und die vollständig gesicherte Zwischenablage nach 1–2 s wiederherstellen, solange kein neuer Inhalt kopiert wurde. Keine Wiederholung bei unklarem Ergebnis.
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

**Ausnahme App-Updates (Eigentümerentscheidung 2026-10-14):** Konfigurierte Release-Builds prüfen bei jedem App-Start unmittelbar nach dem Start des Updaters und danach nach Sparkles Vier-Stunden-Zeitplan per HTTPS auf neue Versionen (Eigentümerwunsch 2026-10-15). Die Startprüfung respektiert eine deaktivierte automatische Update-Suche. Nur verfügbare, nicht übersprungene Updates werden angeboten; ohne Update oder bei fehlender Verbindung erscheint kein Startdialog. Aktive Lese-, Diktier- und Modellinstallationsvorgänge behalten ihren bestehenden Schutz. Einstellungen → Allgemein erlaubt Abschalten und manuelles Prüfen. Der Server sieht IP-Adresse und übliche HTTP-Metadaten; keine Bildschirm-, Text- oder Audiodaten werden übertragen, optionale Systemprofile sind abgeschaltet. Signierte Update-Dateien werden erst auf Nutzeraktion geladen/installiert; ein Neustart wartet auf das Ende aktiver Arbeit. Release-Notizen werden nicht separat nachgeladen. Entwicklerbuilds ohne gültige Feed-Konfiguration starten keinen Updater. Eine fehlende Verbindung blockiert weder Vorlesen noch Diktieren. [Release- und Updateverfahren](release-and-updates.md).

**Ausnahme Diktiermodelle (Eigentümerentscheidung 2026-10-14):** Builds bringen nur
Whisper Turbo mit. Qwen3-ASR und Whisper Large v3 lädt die App ausschließlich, wenn
der Nutzer in Einstellungen → Diktieren „… installieren“ wählt und den Dialog mit
Größe und Quelle bestätigt. Dann ruft die App per HTTPS nur die im mitgelieferten
Manifest gepinnte Hugging-Face-Revision ab; Weiterleitungen sind nur zu
`huggingface.co`/`*.hf.co` erlaubt. Die Anfrage enthält keine Nutzerdaten, keine
Cookies und keinen Cache. Jede Datei wird vor der Nutzung gegen Größe und SHA-256
aus dem Manifest geprüft und erst danach nach
`~/Library/Application Support/Saywing/DictationModels` verschoben; Abbruch oder
Prüffehler hinterlassen nichts. Lizenztexte stammen aus dem App-Bundle. Ein Download, der mehr Bytes als gepinnt
liefert oder eine abweichende Länge ankündigt, wird sofort abgebrochen. Geprüfte
Dateien werden schreibgeschützt (0444) abgelegt; beim Start der Modellverwaltung
werden liegengebliebene `.staging-*`-Ordner eines abgestürzten Laufs gelöscht. Der
Diktier-Worker selbst bleibt ohne Netzwerk, prüft die Hashes beim Laden erneut,
verweigert Modellordner mit nicht im Manifest gelisteten Dateien (ausgenommen
`.DS_Store`, `VERIFIED.json` und die Lizenzkopien `LICENSE-OpenAI`/`LICENSE-Apache-2.0`)
und prüft nach dem Laden, dass Gerät, Inode, Größe und Änderungszeit aller Dateien
unverändert sind. Das verkleinert, beseitigt aber nicht das Zeitfenster zwischen
Prüfung und Laden gegenüber einem Prozess mit denselben Benutzerrechten.
Kein automatischer Download, kein Download beim Start, kein Fallback.

## Speicher- und Lebenszyklus

- Die neue explizit geöffnete Wiedergabeansicht darf bis zu 100 Zeichen je wartendem Text anzeigen. Die geschlossene Kapsel bleibt textfrei. Einträge werden über flüchtige UUIDs bearbeitet; Entfernen/Umsortieren ersetzt gegebenenfalls auch das vorbereitete Audio. Stop leert weiterhin alles und schließt die Ansicht. Pause hält nur die vorhandenen begrenzten RAM-Puffer und die aktive Sitzung, ohne Dateien zu schreiben. Einrichtung speichert ausschließlich `setupDismissed.v1`, niemals ein angeblich bestandenes Berechtigungsergebnis oder einen Fortschritt; der Schritt wird bei jedem Öffnen aus den aktuellen Freigaben abgeleitet.
- Ein privates Packaging-Experiment darf das vorhandene Modell und die gepinnte Runtime als Programmbestandteile in `Contents/Resources/Speech` tragen. Kein Runtime-Download und kein Fallback auf die Entwicklerinstallation, wenn dieser Bundle-Ordner existiert, aber beschädigt ist. Release-Builds verwenden die Entwicklerinstallation unter `~/Library/Application Support/OpenScreenReader` nie und melden ohne Bundle-Ordner „nicht installiert“; nur Debug-Builds dürfen sie nutzen. Der Prüfmodus `--dictation-smoke` existiert ebenfalls nur in Debug-Builds. Redistribution, vollständige Lizenzkette und eine Prüfung auf einem frischen Mac bleiben Release-Gates.

- Vorlesegeschwindigkeit wird als Zahl unter `speechPlaybackRate.v1` gespeichert; der separate Hinzufügen-Shortcut als Taste/Modifikatoren unter `enqueueShortcut.v1`. Keine Audio-, Text- oder Bildschirmdaten werden dadurch gespeichert. Bis zu fünf wartende OCR-Texte mit je maximal 8.000 Zeichen/48.000 UTF-8-Bytes bleiben nur im RAM. Sie werden nach FIFO-Wiedergabe freigegeben; Gesamtstopp, Fehler oder Beenden leeren die Liste und verwerfen verspätete Aufnahme-/OCR-Ergebnisse. Die Liste enthält Text, Auswahlgeometrie und Zählwerte, niemals Screenshots. Der Sprachservice darf ausschließlich für ihren nächsten Eintrag Audio vorab im RAM erzeugen; keine Vorab-TTS der gesamten Liste. Genau ein Worker bleibt innerhalb der Sitzung geladen und bearbeitet Texte seriell. Aktueller und nächster Transportbuffer sowie Player sind auf je acht Sekunden Quell-Audio begrenzt (zusammen rund 4,04 MiB), unabhängig vom Tempo. Dies begrenzt die Swift-PCM-Warteschlangen, nicht In-flight-Pakete, Transportkodierung oder den Gesamtspeicher von Audio-Engine und Modellworker. Stop/Esc/Beenden löschen beide Transportbuffer und die Audioqueue und beenden den warmen Worker. Ohne aktive/vorbereitete Arbeit endet Warmhalten spätestens nach 30 s. Keine neue Datei-Historie, Telemetrie oder Runtime-Netzwerkverbindung.
- Für die Panelposition werden nur `readingPanelEdge` (unten/links/rechts) und `readingPanelOffset` (normierter Versatz 0–1) lokal in UserDefaults gespeichert. Keine Display-ID, absoluten Bildschirmkoordinaten oder Bewegungsaufzeichnungen. Ziehen nutzt nur normale Mausereignisse der eigenen Statusfläche und benötigt keine zusätzliche Berechtigung; die Positionsvorschau startet weder Aufnahme noch OCR oder Sprache.
- Die gewählte Tastenkombination (Taste und Modifikatoren) wird lokal unter `readingShortcut.v1` in UserDefaults gespeichert. Das Kurzbefehlsfeld der Einstellungen wertet nur den einen Tastendruck aus, während es ausdrücklich angeklickt aufnimmt; es speichert keine Tastatureingaben und enthält keine Bildschirm-, OCR- oder Audioinhalte. Währenddessen sind die globalen Kurzbefehle kurz abgemeldet.
- Klick statt Ziehen (Eigentümerfreigabe 2026-10-14, „alles umsetzen“ aus dem Apple-Design-Review): Ein einzelner Klick im Auswahl-Overlay erfasst einen begrenzten Bereich von höchstens 1200 × 800 Punkten um den Zeiger, innerhalb des angeklickten Displays. Nur der Absatz unter dem Zeiger wird vorgelesen; der übrige erkannte Text wird unmittelbar nach der lokalen Texterkennung verworfen, nie angezeigt, gesprochen, eingereiht oder gespeichert. Ein Klick fern von Text liest nichts. Dies ist die einzige Ausnahme von „nur der markierte Bereich“: Der Klick ist die ausdrückliche Markierung.
- Der Auswahlhinweis zählt nur seine Anzeigen unter `selectionHintCount.v1` (höchstens 5).
- Für Interface-Klänge werden nur Ein/Aus unter `interfaceSoundsEnabled.v1` und die Lautstärke unter `interfaceSoundsVolume.v1` lokal gespeichert. Die sechs festen Stereo-Hinweisklänge (Öffnen, Abschluss, Hinweis, teils in zwei Voicings, sowie seit 2026-10-14 Mikrofon an, freihändig eingerastet und Mikrofon aus) werden beim Start mathematisch im Speicher erzeugt; sie verwenden keine Aufnahme, keinen OCR-Text, kein Sprachmodell und keine Netzwerkverbindung. Ihre wiederverwendbaren Puffer enthalten nur diese festen Töne, keine Nutzerinhalte; es werden keine Audiodateien geschrieben. Die Stop-Taste ist seit 2026-10-14 stumm; ihre haptische Rückmeldung nutzt nur die System-API ohne Daten.
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
- Geführte Einrichtung (2026-10-14): Jede Freigabe wird nur durch einen Klick auf ihrer eigenen Seite angefragt. Während Saywing auf eine Freigabe wartet, prüft es deren Status (Preflight, ohne Dialog) und liest aus der Fensterliste des Systems ausschließlich Prozess-ID, Ebene und Rahmen der Fenster der Systemeinstellungen, um den Hinweis daneben zu platzieren. Fenstertitel oder Inhalte anderer Apps werden nicht gelesen, nichts wird gespeichert, und das Abfragen endet mit der Freigabe, beim Wechsel der Seite oder beim Schließen.
- Die Bildschirmerfassung schließt alle eigenen Fenster aus, mit einer Ausnahme: ein sichtbares Fenster mit der Kennung `readableBySaywing`. Das ist derzeit nur das Einrichtungsfenster mit seinem eigenen Beispielsatz, damit der Lesetest ohne privaten Bildschirminhalt auskommt. Statusfläche, Auswahl-Overlay und Hinweise bleiben ausgeschlossen.
- Diktat am Cursor (2026-10-14): Zu Beginn eines Diktats liest Saywing über die Bedienungshilfen nur die Bildschirmposition der Einfügestelle (`AXBoundsForRange` mit Länge 0) oder, ersatzweise, Position und Größe eines kleinen Textfelds. Inhalte werden dafür nicht gelesen, und die Position wird nur bis zum nächsten Diktat im RAM gehalten.
- „Beenden & neu öffnen“ startet `/bin/sh` mit der eigenen Prozess-ID und dem App-Pfad; die Shell wartet auf das Ende von Saywing und öffnet es mit `--resume-setup` erneut. Keine Netzwerk- oder Dateizugriffe.

## Überprüfbarkeit

Der aktuelle Entwicklungspfad überträgt OCR-Text über eine anonyme Pipe an den lokalen Supertonic-Worker, nicht als Kommandozeilenargument oder Datei. PCM wird im Speicher abgespielt. Der Worker läuft im gemeinsamen Worker-Profil (siehe „Worker-Sandbox“); Python läuft ohne Bytecode-Schreibzugriffe und ohne benutzerspezifische Importpfade. Die installierten Modelle und Abhängigkeiten werden ausschließlich im expliziten Entwicklungsschritt bereitgestellt, niemals durch die App nachgeladen. Wiedergabe- und Abbruchtests prüfen außerdem, dass die Zwischenablage unverändert bleibt. Dies ersetzt nicht die noch offene Prüfung des vollständig gebündelten Release-Artefakts. Tatsächliche Prüfergebnisse und Grenzen: [Supertonic-Integration](research/supertonic-integration.md); vorherige Qwen-Messungen bleiben in der [Runtime-Evaluation](research/swift-runtime-evaluation.md) dokumentiert.

Das Repository soll dokumentieren, wie Nutzer die Datenschutzversprechen selbst prüfen können:

1. Offline-Funktionstest unmittelbar nach Installation des vollständigen Release-Artefakts;
2. Netzwerkbeobachtung während OCR und TTS;
3. Kontrolle temporärer Dateien;
4. Kontrolle der Zwischenablage;
5. reproduzierbare beziehungsweise nachvollziehbare Release-Builds;
6. vollständige Third-Party- und Modell-Lizenzübersicht.

## Worker-Sandbox — 2026-10-23

Diktier- und Sprach-Worker starten über `sandbox-exec` mit demselben Profil
(`WorkerSandbox.profile` in der App, byte-gleich als `Runtime/Dictation/worker.sb`
für Skripte und Integrationsprüfungen). Es ist ein Allow-List-Profil
(`deny default`) auf Basis von Apples `bsd.sb`:

- Lesen nur im Runtime-Ordner, im Modellordner, im Präfix des Interpreters, in den
  Systembibliotheken aus `bsd.sb`/`system.sb` und in den Metal-Shader-Caches;
  Metadaten (`stat`) bleiben überall lesbar, Inhalte des Benutzerordners nicht.
- Kein Netzwerk, keine Dateischreibzugriffe außer `/dev/null`, kein `fork`, kein
  `exec` außer dem Interpreter selbst, keine Apple Events.
- Mach-Dienste nur aus der Grundliste von `system.sb` (unter anderem Logging,
  `cfprefsd` lesend, `trustd`) plus `com.apple.MTLCompilerService` und die
  GPU-Clients `AGXDeviceUserClient`/`IOSurfaceRootUserClient` für MLX. Launch
  Services, Zwischenablage (`com.apple.pasteboard.1`), TCC (`tccd`,
  `tccd.system`), WindowServer und `nsurlsessiond` sind ausdrücklich gesperrt.

Geprüft am 2026-10-23 mit der installierten App auf Apple Silicon (macOS 26):
Whisper Turbo, Whisper Large v3 und Qwen3-ASR (installierter Modellordner)
transkribieren die Demos, Supertonic liest und bricht ab; Netzwerk, Schreiben,
Kindprozesse und Lesen außerhalb von Runtime/Modell schlagen fehl.

Verbleibende Grenzen: Das ist kein „Verbot jeder Ausleitung“. Der Worker kann
weiterhin über seine stdout-Pipe an Saywing antworten und die erlaubten
Systemdienste ansprechen. `sandbox-exec` ist von Apple als veraltet markiert und
`bsd.sb` ist private Systemschnittstelle; ändert macOS sie, startet der Worker
nicht mehr (er fällt geschlossen aus, nicht offen). Der Intel-Pfad (whisper.cpp auf
der CPU, Supertonic auf der CPU) wurde unter diesem Profil noch nicht auf echter
Intel-Hardware geprüft. Die Worker erben Saywings TCC-Zuständigkeit (Mikrofon,
Bedienungshilfen, Bildschirmaufnahme); sie selbst greifen auf keine dieser Quellen
zu, und `tccd` ist gesperrt. Eine Abkopplung der Zuständigkeit ginge nur über
private API und wird nicht verwendet.

## Produktkommunikation

Zulässige Aussagen sind beispielsweise:

- „No text or screenshots are uploaded.“
- „Works offline after installation.“
- „No account required.“
- „No telemetry in the official build.“

Nicht verwendet werden sollen absolute, nicht beweisbare Aussagen wie „100 % sicher“.

## Diktieren — Freigabe 2026-10-13

Mikrofonfreigabe und Aufnahme sind getrennte Aktionen. Kein Mikrofonstart beim App-Start, Laden oder Freigeben. Maximal 60 s PCM bleiben im RAM und laufen über anonyme Pipes an das ausgewählte lokale Diktiermodell. Der Worker läuft im gemeinsamen Worker-Profil (siehe „Worker-Sandbox“): ohne Netzwerk, Dateischreiben (außer `/dev/null`), Kindprozesse und Zugriff auf Dateien außerhalb von Runtime und Modell. Er lädt ausschließlich mitgelieferte oder ausdrücklich installierte, hashgeprüfte Modelle; kein Cloud- oder Entwicklerpfad-Fallback. Modellauswahl, Sprache und Restore-Verzögerung sind die gespeicherten Diktiereinstellungen. Das sichtbare letzte Ergebnis/Testfeld bleibt bis Verwerfen/Leeren/Beenden im RAM, ohne Verlauf.

Beim Diktat werden Feldinhalt und Cursorposition, sofern verfügbar, nur zur Zielvalidierung im RAM gehalten. Passwortfelder und nicht erkannte Felder werden abgewiesen. Alle lesbaren Clipboard-Formate werden vor dem Einfügen bis 16 MiB gesichert; nicht vollständig sicherbare Daten verhindern automatisches Einfügen. Eine neue Kopie hat Vorrang. Zugesagte Dateien (File Promises) werden schon anhand der Typliste abgewiesen, bevor eine App Daten erzeugen muss. Abbruch/normaler App-Exit stellt eine noch eigene Zwischenablage sofort wieder her; ein harter Absturz im kurzen Einfügefenster kann dies verhindern. Der eingefügte Text trägt die nspasteboard.org-Kennzeichen `ConcealedType`, `TransientType` und `AutoGeneratedType`; Text und Wiederherstellung werden mit `currentHostOnly` geschrieben und gelangen nicht in die universelle Zwischenablage anderer Geräte. Clipboard-Manager, die diese Kennzeichen ignorieren, können den Text dennoch sehen.

**Passwortmanager (Entscheidung 2026-10-23):** Trägt die gesicherte Zwischenablage eines dieser drei Kennzeichen, etwa ein von einem Passwortmanager kopiertes Passwort, wird sie nach dem Einfügen geleert statt wiederhergestellt – ebenfalls nur, solange der eingefügte Text noch Saywing gehört; eine neuere Kopie hat weiter Vorrang. Ein Zurückschreiben sähe für den Passwortmanager wie eine neue Kopie aus und verhinderte sein zeitgesteuertes Leeren; das Passwort bliebe unbegrenzt liegen. Die Statuszeile sagt dem Nutzer, dass geleert statt wiederhergestellt wurde. Die manuelle Aktion „Ergebnis kopieren“ behält die ausdrücklich angeforderte Kopie.

Mikrofon und Bedienungshilfen werden ausschließlich per Einrichtungsbutton angefragt; keine Liveaufnahme durch Demos oder Selbsttests. Vorlesen stoppt vor einer Aufnahme, ein Vorlesestart verwirft aktives Diktieren. Esc, Verwerfen, Systemruhe/Sitzungswechsel und App-Ende räumen aktive Aufträge auf und invalidieren verspätete Ergebnisse. [Details und Nachweise](research/qwen-dictation-runtime.md).

## Fn-Diktiersteuerung — 2026-10-13

Auf Wunsch des Eigentümers unterstützt Diktieren Fn-Halten, Fn-Doppeldruck und Fn+Leertaste. Mit Bedienungshilfenfreigabe beobachtet ein Event-Tap Fn-/Modifier-Übergänge und Tastendruck-/Loslass-Ereignisse, damit er Fn+Leertaste übernehmen und andere Fn-Kombinationen durchlassen kann. Er liest keine Zeichen, speichert keine Tastaturtexte und überträgt keine Tastendaten; sein Zustand umfasst ausschließlich Fn-Gesten, Zeitpunkte und die zugehörige Leertaste. Andere Tasteneingaben werden unverändert durchgereicht. Der Tap läuft während der verfügbaren Fn-Steuerung, wird bei Ruhezustand/Sitzungswechsel/Beenden entfernt und bricht eine aktive Fn-Aufnahme bei Verlust der Beobachtung ab. Anders als die bisherige Escape-Beobachtung besteht er deshalb auch zwischen Aufnahmen. Freigaben werden nicht automatisch angefragt. ⌥⇧Leertaste bleibt ohne Fn-Beobachtung nutzbar.

## Auswahl des Diktiermodells — 2026-10-13

Qwen3-ASR, Whisper Turbo und Whisper Large v3 verwenden dieselbe Offline-Sandbox und die bestehende
flüchtige Audio-/Clipboard-Pipeline. `dictationModel.v1` speichert nur die Wahl des
Modells. Laden und Wechsel starten kein Mikrofon. Fehlende oder beschädigte
Modelldateien erzeugen einen sichtbaren Fehler; die App lädt nichts automatisch aus
dem Netz und wechselt nicht automatisch auf einen anderen Provider. Nicht
mitgelieferte Modelle werden nur nach ausdrücklicher Bestätigung installiert (siehe
„Netzwerkzugriffe“). Wechsel invalidieren
Callbacks des alten Workers. Quelle, Revision, Prüfsummen und Lizenz von [Whisper
Turbo](research/whisper-turbo-dictation.md) und [Whisper Large
v3](research/whisper-large-v3-dictation.md).

## Standardmodell und eigenes Vokabular — 2026-10-14

Whisper Turbo ist das Standardmodell für neue Installationen; eine gespeicherte
Wahl bleibt erhalten. Unter Einstellungen → Diktieren kann ein eigenes Vokabular
(höchstens 50 Begriffe zu je 60 Zeichen) eingetragen werden. Es wird nur lokal unter
`dictationVocabulary.v1` gespeichert, enthält ausschließlich die selbst
eingetragenen Begriffe und wird bei jedem Diktat über die anonyme Pipe an den
Offline-Worker übergeben. Weder Worker noch App protokollieren oder übertragen es.
Ein geleertes Feld entfernt den Eintrag. Diktierte Texte werden dadurch nicht
gespeichert und nicht automatisch ins Vokabular übernommen.

### Setup preferences (2026-10-14)

Setup additionally saves the dictation shortcut, optional Fn setting and the model identifier of an explicitly requested installation. It never saves microphone audio, screen content or recognized text. Restoring an interrupted installation does not resume network requests automatically: another explicit download confirmation is required. Capturing a shortcut suspends activation keys, including Fn, so entering a combination cannot start recording. Downloads continue to use only the approved pinned manifests and verify every installed file before activation.

## Meeting-Mitschrift — Eigentümerentscheidung 2026-10-15

[ADR 0006](decisions/0006-local-meeting-transcript.md). Eine enge Ausnahme von „keine Aufnahme anderer Inhalte“, nur für eine ausdrücklich gestartete Mitschrift.

- **Start nur nach Einwilligungs-Schritt:**
  - Vor jedem Start erklärt ein Fenster, was aufgenommen wird, und bietet einen kopierbaren Hinweis für den Meeting-Chat.
  - Der Hinweis wird nur auf Klick kopiert.
  - Kein automatischer Start, keine Meeting-Erkennung, kein Posten in andere Apps.
- **Zwei Quellen:**
  - das Mikrofon („Ich“);
  - das Systemaudio aller anderen Apps („Andere“) über einen privaten Core-Audio-Prozess-Tap, der Saywing selbst ausschließt. Saywings eigenes Vorlesen gelangt so nicht in die Spur „Andere“.
  - Die Systemaudio-Freigabe fragt macOS beim ersten Start (`NSAudioCaptureUsageDescription`); Saywing nutzt keine private TCC-Schnittstelle.
- **Erkennung:**
  - Apples `SpeechTranscriber` auf dem Gerät (macOS 26 oder neuer), nur für bereits installierte Sprachen.
  - Saywing fordert keine Sprachmodelle aus dem Netz an und hat in diesem Pfad keinen eigenen Netzwerkzugriff.
  - Der Diktier-Worker wird nicht benutzt.
- **Keine Dateien, kein Verlauf:**
  - Audio liegt nur in kurzen Puffern im RAM, für die Erkennung und das Echo-Gate (je Spur höchstens etwa 2 s bei 8 kHz), und wird laufend verworfen.
  - Kein Audio auf der Festplatte.
  - Das Transkript bleibt nur im RAM, bis es verworfen, durch eine neue Mitschrift ersetzt oder die App beendet wird.
  - Schreiben nur über „Kopieren“ (ausdrücklicher Klick) oder „Sichern …“ (Speicherdialog, Markdown).
  - Keine neuen Einstellungs-Schlüssel.
- **Ende:**
  - Stopp, 2-h-Grenze (Hinweis 5 min vorher), 10 min Stille auf beiden Spuren, Systemruhe, Sitzungswechsel und App-Ende beenden die Aufnahme. Das Transkript bleibt bis zum Verwerfen erhalten.
  - Esc, Vorlesen und Diktieren beenden sie nicht.
  - Verspätete Erkennungsergebnisse nach dem Ende werden verworfen.
- **Anzeige:** Während der Aufnahme trägt das Menüleistensymbol einen Ring, und das Menü zeigt „Mitschrift läuft“.
- **Recht:** Die Aufnahme anderer Personen braucht deren Einwilligung (z. B. § 201 StGB, DSGVO). Saywing erinnert daran, prüft es aber nicht. Eine rechtliche Prüfung bleibt Release-Gate.

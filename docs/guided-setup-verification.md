# Geführte Einrichtung — Verifikation

## Integration mit PR #6 — 2026-10-14

`main` bei `e968ddb` wurde in den bestehenden PR-Branch integriert, ohne dessen
veröffentlichte Historie umzuschreiben. Die Konflikte im Diktiercontroller und im
String-Katalog sind aufgelöst: gemeinsame Hinweisklänge und geführte Einrichtung
bleiben zusammen mit dem Modell-Store, den bestätigten Modellinstallationen und
allen neuen Übersetzungen erhalten.

Der zuvor nur lokal vorhandene Startup-Fix ist ebenfalls übernommen: Das
Diktierfenster wird erst beim Öffnen explizit eingepasst und einmalig zentriert,
damit AppKit während der SwiftUI-`StateObject`-Initialisierung kein Layout erzwingt.
Spätere Öffnungen erhalten die Fensterposition; das dynamische Einpassen des
Ergebnisbereichs bleibt bestehen. Der neue Regressionstest schlug vor dem Fix
fehl und besteht danach; er prüft auch, dass keine Mikrofonaufnahme startet.

Tatsächlich auf dem integrierten Stand ausgeführt:

- Native App-Tests: **173 Tests in 12 Suites bestanden**. Zwei zusätzliche
  berechtigungsabhängige XCTest-Prüfungen wurden wegen fehlender Bildschirmaufnahme
  und Eingabeüberwachung übersprungen; der ausdrücklich aktivierbare
  Live-Modelldownload-Test blieb deaktiviert.
- `swift test`: **1 Test bestanden**.
- Python-Protokolltests mit der vorhandenen gebündelten Python-Runtime:
  **19 Tests bestanden**. Keine Modellinferenz und kein Download.
- `scripts/check-localization.py` und `git diff --check`: bestanden.
- Unsigned Release-Build: **BUILD SUCCEEDED**.
- Nativer UI-Test `testSettingsExplainCapturePrivacyAndPermissionActions`:
  **bestanden** (Allgemein-/Datenschutz-Einstellungen und Berechtigungsanzeige).
- Der gebaute Release-Prozess blieb sowohl beim normalen Start als auch mit
  `--dictation-setup` fünf Sekunden aktiv und wurde anschließend gezielt beendet.
  Diese Starts verwendeten keine Testhost-Flags und ersetzen keine Prüfung mit
  vollständig gebündelten Modellen. Die installierte App wurde nicht ersetzt.

Die unten aufgeführten manuellen Freigabe-, VoiceOver-, Ziel-App- und
Distributionsprüfungen bleiben offen. Die UI-Test-Ausführung oben ersetzt nur
die frühere Einschränkung für diesen einen Smoke-Test. Lokale Logs liegen unter
`/tmp/saywing-pr5-*.log`.

Stand 14.10.2026, Branch `codex/guided-setup`. Grundlage ist der Vorschlag nach dem [Apple-Design-Skill von Emil Kowalski](https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md), den der Eigentümer zur Umsetzung freigegeben hat. Die Prinzipien wurden auf SwiftUI/AppKit übertragen; kein fremder Code wurde übernommen. Verhalten und Gestaltung: [UX-Anforderungen › Geführte Einrichtung](ux-requirements.md#geführte-einrichtung).

## Korrigierter Widerspruch

Die bisherige Einrichtung nannte Eingabeüberwachung „optional“ und bot den Lesetest schon mit Bildschirmaufnahme allein an. `AppModel.beginCapture` bricht ohne Eingabeüberwachung jedoch mit Fehler ab, wie es ADR 0005 verlangt: Der Test endete also immer in „Error“. Die Einrichtung führt die Eingabeüberwachung jetzt ehrlich als Teil von „Vorlesen“. Am Esc-Verhalten selbst hat sich nichts geändert.

## Umgesetzt und automatisch geprüft

| Verhalten | Nachweis |
| --- | --- |
| Reihenfolge nur aus aktuellen Freigaben; erteilte Schritte und Tests ohne Grundlage werden übersprungen; Rückkehrer starten beim ersten fehlenden Schritt; Einstieg über das Diktieren | `freshSetupWalksReadingThenOffersDictation`, `setupSkipsGrantedStepsAndTestsThatCannotRun` |
| Lesetest-Erfolg nur nach gespielter Sprache; Esc während der Auswahl ist kein Ergebnis, Esc während des Vorlesens ist Erfolg; „Kein Text“ und Fehler getrennt | `readingTrialConfirmsOnlyHeardSpeech` |
| Lesetest erst mit Bildschirmaufnahme **und** Eingabeüberwachung | `readingTestNeedsScreenRecordingAndInputMonitoring` |
| Erfassung liest nur sichtbare eigene Fenster mit `readableBySaywing`, sonst keine eigenen Fenster | `captureIncludesOnlyVisibleWindowsThatOptIn` |
| Fehlende Lese-Freigabe öffnet die Einrichtung vor der Auswahl, ohne etwas anzufragen und ohne `setupDismissed.v1` zu setzen | `missingReadingPermissionOpensSetupBeforeSelection` |
| Jede Seite hell/dunkel, Englisch und Deutsch, als Bild gerendert und angesehen | `WindowPreviewTests` (`setup-*.png`) |

## Tatsächliche Ergebnisse

- App-Tests: **153 Tests in 10 Suites bestanden**, rund 8,3 s; die zwei berechtigungsabhängigen XCTest-Live-Prüfungen wurden wie bisher übersprungen, weil der Test-Host keine Bildschirmaufnahme und keine Eingabeüberwachung hat. In einem von vier vollständigen Läufen schlug der vorhandene, unveränderte Test `queueCaptureTimeoutDoesNotInterruptSpeechOrAcceptItsLateResult` (Zeitlimit 120 ms) einmal fehl. Allein lief er zweimal grün, danach zwei vollständige Läufe hintereinander grün. Das Zeitlimit ist unter Last zu knapp; das ist kein Fehler der Einrichtung.
- Release-Build ohne Signatur: erfolgreich. `swift test`: erfolgreich. `scripts/check-localization.py`: bestanden; 57 neue deutsche Einträge, 7 nicht mehr verwendete entfernt.
- Vorschauen in Englisch und mit `-testLanguage de` geprüft. Dabei gefunden und behoben: fehlender Fensterhintergrund (dunkle Vorschau unlesbar), Symbol und Titel sprangen je nach Seiteninhalt vertikal, das SF-Symbol `escape` war nicht als Taste erkennbar (jetzt Tastenkappe „esc“), alter Name „Bildschirmaufnahme“ statt „Bildschirm- & Systemaudioaufnahme“ unter macOS 15+, holpriger deutscher Titel. Außerdem lässt sich das Fenster nicht mehr über den Hintergrund verschieben, damit ein Ziehen über den Beispielsatz nicht das Fenster bewegt.

## Nicht verifiziert (manuell mit installierter App nötig)

Diese Pfade brauchen echte TCC-Freigaben und Systemdialoge. Sie wurden nicht ausgeführt und sind deshalb nicht als funktionierend verbucht:

1. Ganzer Durchlauf auf einem Mac ohne Freigaben: Systemdialoge, automatisches Erkennen der Freigabe, Häkchen, Rückkehr von Saywing nach vorn und automatisches Weiterblättern.
2. Hinweis neben den Systemeinstellungen: Position bei verschiedenen Fenstergrößen und auf mehreren Bildschirmen, und ob das Ziehen des App-Symbols in die Freigabeliste unter macOS 14 und 15 wirklich angenommen wird.
3. Ob Bildschirmaufnahme auf der Zielversion einen Neustart braucht, und „Beenden & neu öffnen“ inklusive Fortsetzen mit `--resume-setup`.
4. Lesetest im Fenster: echte Erfassung des Beispielsatzes durch die Ausnahme für das Einrichtungsfenster, OCR, Sprache und Esc.
5. „Hier wohnt Saywing“ unter dem echten Menüleistensymbol. Das Symbol wird über das Statusleistenfenster der App gefunden; fehlt es, wird kein Hinweis gezeigt.
6. VoiceOver-Ansagen und Tastaturbedienung im laufenden Fenster.

Offen ist auch die Idee, für Diktier-Nutzer auf die Eingabeüberwachung zu verzichten, weil die Bedienungshilfen vermutlich auch die Esc-Erkennung erlauben. Sie ist nicht umgesetzt: Dafür braucht es Gate E aus ADR 0005 mit echten Freigaben.

## Rückmeldung am Ort des Geschehens

Zweiter Teil derselben Arbeit (Eigentümerfreigabe „setze das alles um“). Verhalten: [UX-Anforderungen](ux-requirements.md#rückmeldung-am-ort-des-geschehens).

**Rückschritt behoben:** Nach der geführten Einrichtung führte das „?“ einer gescheiterten Lesekapsel bei vollständigen Freigaben zum Lesetest, ohne die Fehlermeldung zu zeigen. Jetzt erklärt ein Popover an der Kapsel den Grund.

| Verhalten | Nachweis |
| --- | --- |
| „?“ erklärt den Fehler an der Kapsel; Einrichtung nur bei fehlender Freigabe, Kurzbefehl-Einstellungen bei belegtem Kurzbefehl, sonst „Erneut versuchen“ | `errorHelpExplainsInPlaceAndOffersSetupOnlyForMissingGrants`, Vorschau `reading-error-help` |
| Diktierkapsel unter der Einfügestelle, darüber bei Platzmangel, immer auf dem Bildschirm, sonst an der angedockten Stelle des Vorlesens | `dictationCapsuleAppearsBelowTheCaretAndFallsBackToTheReadingPlace`, `testFieldCaretIsInScreenCoordinates` |
| Diktierklänge passend zum sichtbaren Ergebnis, nie während der Aufnahme | `dictationCuesMatchItsVisibleResult` |
| Ergebnisbereich nur, wenn nicht eingefügt wurde | `dictationResultAppearsOnlyWhenNotPasted`, Vorschau `dictation-window` |
| Menüleistensymbol: drei unterscheidbare, zwischengespeicherte Vorlagenbilder; Fehler ergibt „Achtung“ | `menuBarIconShowsReadingAndAttentionByShape` |

**Barrierefreiheit:** Ein eigener Prüfagent hat den Code gelesen und 15 Befunde geliefert; VoiceOver lief dabei nicht.
- Umgesetzt:
  - Ansagen für Diktat, Pause, Warteschlange, Overlay, Kurzbefehl-Hinweise und Warten; Fehler mit hoher Priorität, keine Ansage zum Sprechbeginn oder während einer Aufnahme.
  - Return im Overlay; Tab verlässt das Diktier-Testfeld.
  - Steuerelemente der Kapsel sichtbar bei VoiceOver oder Schaltersteuerung.
  - Benannte Warteschlangen-Zeilen und Kurzbefehlsfelder.
  - Kontrast der Status-Texte; Auswahlrahmen mit Außenlinie.
  - Unbestätigtes Einfügen in Bernstein mit Ausrufezeichen.
  - Fokus auf den Seitentitel in der Einrichtung.
  - Menüeinträge „Fertig & einfügen“ und „Diktieren ausprobieren …“.
  - Fokus für die über das Menü geöffnete Wiedergabesteuerung.
  - Finder-Aktion und „+“-Hinweis als Alternative zum Ziehen.
  - Dekorative Elemente vor VoiceOver verborgen.
- Bewusst nicht umgesetzt: die Pfeiltasten im Overlay, die den Systemzeiger verschieben würden.
- Der UI-Smoke-Test wurde an das verborgene Logo und den unter macOS 15 umbenannten Bereich angepasst, aber nicht ausgeführt (Automatisierungsmodus braucht eine Bestätigung am Gerät).

**Ergebnisse:**
- **159 App-Tests in 11 Suites bestanden**, zweimal hintereinander; die zwei berechtigungsabhängigen Live-Prüfungen wurden wie bisher übersprungen.
- Nach dem Rebase auf `main` (mit dem Whisper-Vokabular aus PR #4): **162 App-Tests in 11 Suites bestanden**, zweimal hintereinander. Release-Build und `swift test` erfolgreich, Katalog gültig und vollständig.
- Release-Build, `swift test` und `scripts/check-localization.py` erfolgreich.
- Vorschauen in Englisch und Deutsch angesehen. Dabei behoben: abgeschnittenes „Einrichten & testen…“ im Fehler-Popover und der nutzlose „Erneut versuchen“-Knopf bei belegtem Kurzbefehl.

**Nicht verifiziert:**
- **Live-Prüfung der Bewegung (Punkt 7):** blockiert, weil dieser Prozess keine Bildschirmaufnahme-Freigabe hat („could not create image from display“). Außerdem liefen gleichzeitig die installierte App und ein Testlauf eines anderen Threads. Für eine eigene Prüfung: mit ⌘⇧5 aufnehmen und in QuickTime mit den Pfeiltasten Bild für Bild durchgehen, und zwar für den Seitenwechsel, das Häkchen, das Diktat am Cursor, das Werfen der Kapsel und das Fehler-Popover.
- Ein Durchgang mit VoiceOver und nur mit der Tastatur: ob Esc das Popover schließt, ⌘W die Fenster schließt, die Ansagen nicht kollidieren und die Fokuslandung auf dem Seitentitel wirkt.
- Die Einfügestelle in echten Apps: Safari, Mail, Notizen, Electron-Apps, Terminal.

# Apple-Design-Verfeinerung — Verifikation

Stand 14.10.2026, Branch `codex/apple-design-refinements`. Grundlage ist das Review nach dem [Apple-Design-Skill von Emil Kowalski](https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md); der Eigentümer hat alle 16 Punkte zur Umsetzung freigegeben, einschließlich „Klick liest Absatz“ und stummer Stop-Taste. Prinzipien wurden auf AppKit/SwiftUI übertragen; kein fremder Code wurde übernommen.

## Umgesetzt

| Bereich | Änderung | Nachweis |
| --- | --- | --- |
| Einrichtung | Ein Ablauf für Vorlesen und Diktieren, veralteter Hinweis „Diktieren nicht verfügbar“ entfernt, Test nur mit Bildschirmaufnahme möglich | `readingTestNeedsOnlyScreenRecording`, Vorschau `setup` |
| Freigaben | Status, Zweck und direkter Link in den passenden Systemeinstellungs-Bereich, identisch in Einrichtung und Einstellungen | `permissionsOpenTheirOwnPrivacyPane` |
| Einstellungen | Tabs Allgemein · Vorlesen · Diktieren · Kurzbefehle · Datenschutz; kurze Erklärungen in `.callout`; kein doppelter Rand | Vorschauen `settings-*` (hell/dunkel, en/de) |
| Kurzbefehl | Aufnahmefeld statt Checkboxen; globale Kurzbefehle pausieren währenddessen; Zusatz-Kurzbefehl unter „Erweitert“ | `recordedKeystrokesBecomeShortcutConfigurations`, `recordingAShortcutSuspendsBothGlobalShortcuts` |
| Diktieren | Modell, Sprache, Clipboard-Wartezeit in den Einstellungen; Testfenster mit Systemtextstilen; Demos nur Debug; kein Drittanbieter-Name | `languageAndClipboardDelayArePersistedPreferences`, Vorschau `dictation-window` |
| Menü | Status zuerst, Hauptaktion mit Kurzbefehl, Wiedergabe-Abschnitt nur beim Vorlesen, Fehler mit „Einrichtung öffnen…“ | `menuShowsFeedbackOnlyWhenItAddsInformation` |
| Sprache | Englische Quelltexte, 290 deutsche Einträge inkl. Plural, InfoPlist lokalisiert, Worker-Meldungen über Codes | `germanLocalizationShipsInTheAppBundle`, `germanTableCoversTheWholeCatalog`, `scripts/check-localization.py` |
| Klänge | Stop-Taste ohne Tick/Tock; drei Hinweisklänge bleiben | `stopButtonPressIsSilentAndCuesKeepToMeaningfulMoments` |
| Auswahl | Leertaste/Umschalt/Wahl wie ⌘⇧4; 90-ms-Einblendung der Abdunklung; Hinweis bei den ersten fünf Auswahlen | `selectionGestureFollowsScreenshotModifiers`, `selectionHintAppearsForTheFirstFewSelectionsOnly`, Vorschau `selection-hint` |
| Klick liest Absatz | Begrenzter Bereich (≤ 1200 × 800 pt), nur der Absatz unter dem Zeiger wird gelesen | `clickSelectsABoundedAreaAroundThePointer`, `clickedBlockKeepsOnlyItsParagraphInReadingOrder`, `realVisionBoxesFindTheClickedParagraph` (echtes Vision) |
| Andocken | Wurf-Projektion (0,998), Feder je Achse mit Geschwindigkeitsübergabe, Gummiband am Rand, Haptik beim Einrasten | `flickedControlLandsWhereItsMomentumPoints`, `dragVelocityUsesOnlyTheLastMomentBeforeRelease`, `springsSettleFromTheirCurrentVelocityWithoutDecorativeOvershoot`, `edgesResistProgressivelyInsteadOfStoppingHard` |
| Flug | Ease-out, 380 ms statt 460 ms | `selectionFlightRespondsImmediately` |

## Tatsächliche Ergebnisse

- App-Unit-Tests (Englisch erzwungen über das Schema): **148 Tests in 10 Suites bestanden**, rund 8,4 s; zwei berechtigungsabhängige XCTest-Live-Prüfungen übersprungen, wie zuvor.
- Fenster-Vorschauen (`TEST_RUNNER_OSR_WINDOW_PREVIEW_DIR`) in Englisch und mit `-testLanguage de` in Deutsch gerendert und visuell geprüft, jeweils hell und dunkel. Dabei gefunden und behoben: abgeschnittener Hinweistext im Diktierfenster, Hinweis-Pille zu knapp, Kurzbefehlsfeld nicht auf einer Linie mit dem Label.
- Release-Build ohne Signatur: erfolgreich. `swift test`: erfolgreich. `OpenScreenReaderCoreBehaviorChecks`: alle 11 bestanden.
- Python-Diktierworker-Tests (`Tests/Dictation/test_worker.py`) mit dem gebündelten Interpreter gegen das Repository-`worker.py`: 10 bestanden.
- `scripts/check-localization.py`: bestanden.

## Grenzen und offene Punkte

- **UI-Tests nicht gelaufen:** `xcodebuild test -only-testing:OpenScreenReaderUITests` brach mit „Timed out while enabling automation mode“ ab. macOS verlangt dafür eine Bestätigung am Gerät. Die UI-Tests sind an Tabs, Aufnahmefeld und Menü angepasst und kompilieren, wurden aber nicht ausgeführt.
- Nicht live geprüft: Gefühl von Wurf und Feder, Leertaste/Umschalt/Wahl im echten Overlay, Klick-Absatz auf echten Bildschirminhalten, Tastenkürzel-Anzeige im Menüleisten-Menü, Toolbar-Tabs im echten Settings-Fenster.
- `queueCaptureTimeoutDoesNotInterruptSpeechOrAcceptItsLateResult` nutzt ein Zeitbudget von 120 ms und schlug in einer Phase bei parallel laufenden Suiten zweimal fehl, danach in sechs Läufen nicht mehr. Allein ausgeführt war die Suite stabil. Der Test wurde nicht aufgeweicht.
- Ein Zwischenstand las Repository-Dateien aus dem Test-Host; das kann eine macOS-Abfrage für den Ordner „Dokumente“ ausgelöst haben. Der Test liest jetzt nur noch das gebaute Bundle.
- Das installierte `/Applications/Saywing.app` enthält noch den alten Diktierworker mit deutschen Meldungen ohne Code; die Swift-Seite zeigt diese unverändert an, bis die Laufzeit neu gebündelt wird.
- Klick-Absatz erkennt Absätze über Zeilenabstand, Überlappung und Zeilenhöhe. Mehrspaltige Layouts mit sehr engem Spaltenabstand oder Tabellen können abweichen; ein Absatz am Rand des 1200 × 800-pt-Bereichs kann abgeschnitten sein.

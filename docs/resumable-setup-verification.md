# Fortsetzbare Einrichtung — 2026-10-14

Branch: `codex/resumable-permission-setup`. Grundlage: Eigentümerauftrag zur
Wiederaufnahme nach Berechtigungs-Neustarts und der bereits gelesene
[Apple-Design-Skill](https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md).
Nur Designprinzipien übertragen, keinen fremden Code übernommen.

> Historischer Prüfstand vor der Integration mit dem inzwischen erweiterten geführten Ablauf auf `main`. Die aktuellen Prüfungen stehen in [Einrichtung: Modelle und Kurzbefehle](setup-models-shortcuts-verification.md).

## Verhalten

- Ein nativer Ablauf mit sechs Schritten: Bildschirmaufnahme, optionale
  Eingabeüberwachung, Vorlesetest, Mikrofon, Bedienungshilfen, Diktiertest.
- Der Fortschritt wird vor beiden externen Aktionen gespeichert: Freigabe
  anfragen und Systemeinstellungen öffnen. Das gilt auch bei einer zuvor
  abgeschlossenen, später manuell wieder geöffneten Einrichtung.
- Unvollständige Einrichtung öffnet direkt beim App-Start. Frische
  Berechtigungsprüfungen überspringen erlaubte Schritte, niemals Testaktionen.
  Entzogene erforderliche Freigaben führen zum passenden Schritt zurück.
- „Später“ bewahrt den Schritt ohne automatische Wiederöffnung. Abschluss
  löscht den Checkpoint. Weder Fortsetzen noch Freigeben startet Mikrofon,
  Bildschirmaufnahme, OCR oder Sprachwiedergabe.
- Bedingte Neustart-Hilfe statt einer behaupteten Neustartpflicht. Der lokale
  Helfer wartet höchstens 30 Sekunden auf das alte Prozessende und öffnet
  dasselbe Bundle. Pfade werden als Argumente übergeben, nicht in Shellcode
  eingesetzt. Startfehler lassen die App offen; kehrt der Beendigungsaufruf
  zurück, wird der Helfer abgebrochen. Aktive Vorgänge, Kurzbefehlsaufnahme und
  Modellinstallation sperren den Neustart.
- Englische Quelltexte und vollständige deutsche Übersetzungen. Neutrale
  ausstehende Freigaben, Zweck direkt an der Aktion, nativer Hilfeabschnitt.

## Ausgeführte Prüfungen

- TDD: neue Wiederaufnahme-Tests zuerst ausgeführt; erwarteter Buildfehler
  wegen des noch fehlenden `SetupProgress`. Danach sechs neue Verhaltenstests
  erfolgreich, anschließend um Neustartfehler und Sperre bei
  Kurzbefehlsaufnahme erweitert.
- Vollständige App-Tests: **167 Swift-Testing-Tests in 12 Suites bestanden**.
  Die später hinzugefügte optionale Vorschauprüfung ist in dieser Zahl noch
  nicht enthalten. Zwei zusätzliche XCTest-Live-Prüfungen für Bildschirmaufnahme
  und globales Escape wurden wegen fehlender Testhost-Berechtigungen übersprungen;
  der opt-in Live-Modell-Download blieb ebenfalls übersprungen.
- Finaler fokussierter Lauf: **9 Tests bestanden**, einschließlich
  Vorschau-Export. Damit sind acht Verhaltenstests plus Layout-Export geprüft.
- Echter UI-Test `testSetupResumesAtTheSameStepWithoutOpeningTheMenu`:
  **bestanden**. Frische isolierte Einstellungen, Einrichtung automatisch
  geöffnet, Diktieren ausgewählt, Prozess beendet und neu gestartet: dieselbe
  Seite wieder sichtbar, ohne Menü-Klick. Danach „Später“, erneuter Neustart:
  keine automatische Einrichtung. Keine Berechtigungen wurden dafür geändert.
- Der erste UI-Lauf wurde durch das davorliegende Codex-Fenster unterbrochen.
  Nach expliziter App-Aktivierung vor Klicks bestand der Test (14,27 s).
- Alle sechs Zustände auf Deutsch in Hell/Dunkel gerendert. Bildschirmfreigabe,
  optionale Eingabeüberwachung und Diktiertest visuell geprüft: Textumbruch
  ohne Abschneiden. Die Render-Prüfung verwendet simulierte Freigaben; sie
  belegt Layout, keine echten Systemfreigaben.
- `scripts/check-localization.py` und `git diff --check`: bestanden.
- Release-Build mit `CODE_SIGNING_ALLOWED=NO`: **BUILD SUCCEEDED**.
  Das ist ein Kompilierungsnachweis, kein signiertes Distributionsartefakt.

## Grenzen

- Die ursprüngliche macOS-Neustartaufforderung nach erstmaliger Freigabe wurde
  nicht durch Zurücksetzen bestehender TCC-Berechtigungen nachgestellt. Der
  tatsächliche Neustartbedarf bleibt versions- und berechtigungsabhängig;
  [Apples ScreenCaptureKit-Beispiel](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)
  beschreibt einen Neustart nach der ersten Bildschirmaufnahme-Freigabe.
- Der UI-Test beendet und startet die App über XCTest. Der vollständige
  Neustart-Button mit nachgelagertem LaunchServices-Helfer wurde noch nicht
  als echter Ende-zu-Ende-Ablauf ausgeführt; Fehler-/Checkpoint-Verhalten ist
  injiziert getestet. Die Hilfe behauptet nicht, eine Freigabe sei allein
  durch Neustarten erteilt.
- Kein Release, keine Installation nach `/Applications`, kein Commit oder Push.
  Andere bereits vorhandene Workspace-Änderungen wurden beibehalten.

Lokale Nachweise: `/tmp/saywing-setup-tests.log`,
`/tmp/saywing-setup-ui.log`, `/tmp/saywing-setup-previews.log`,
`/tmp/saywing-setup-previews-de/`, `/tmp/saywing-setup-release.log`.

# Einrichtung: Modelle und Kurzbefehle — 2026-10-14

Branch: `codex/setup-models-shortcuts`. Umsetzung des Eigentümerauftrags nach dem
[Apple-Design-Skill](https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md).
Übernommen wurden Gestaltungsprinzipien, kein fremder Programmcode.

## Verhalten

- Pro Aktivität: Freigaben → Modell → Kurzbefehle → Ausprobieren. Gespeicherte
  Checkpoints bleiben kompatibel. Neustarts übernehmen den aktuellen Schritt;
  tatsächliche Systemfreigaben werden erneut geprüft. Modell und Kurzbefehle
  lassen sich auch vor Erteilen der Berechtigungen konfigurieren.
- Native Auswahl für Vorlesen/Diktieren, feste Fenstergröße, scrollbarer Inhalt
  und feste Navigation. Modellwahl und Kurzbefehlsfelder werden mit den
  Einstellungen geteilt. Deutsche und englische Texte; Hell-/Dunkelansicht.
- Whisper Turbo zuerst, weitere Modelle aufklappbar. Installierte Modelle können
  direkt gewählt werden. Zulässige fehlende Modelle benötigen eine ausdrückliche
  Downloadbestätigung mit Größe und Herkunft. Download und Dateiprüfung haben
  getrennte, abbrechbare Zustände. Keine neuen Quellen oder Modellgewichte.
- Unterbrochene Installationen bewahren nur den gewünschten Modellbezeichner und
  bieten einen erneuten bestätigten Versuch. Kein automatischer Download beim
  Wiederöffnen. Auswahlwechsel und Abbruch schützen vor verspäteter Aktivierung.
- Eigene Aufnahmefelder für Vorlesen und Diktieren, Fn separat abschaltbar.
  Registrierung vor Speicherung, Konfliktprüfung gegen alle drei Kurzbefehle,
  Warnung bei reinen Command-Kombinationen. Während der Tastenaufnahme sind
  Vorlesen, Warteschlange, Diktieren und Fn pausiert. Escape bleibt Abbruch.

## Ausgeführte Prüfungen

- TDD: sechs neue Konfigurationstests zunächst mit den erwarteten fehlenden APIs
  fehlgeschlagen, nach Umsetzung erfolgreich. Zusätzlich Persistenz der neuen
  Einrichtungsphasen getestet. Bestehende Tests an die expliziten Zwischenstufen
  angepasst, ohne Tests oder Freigaben als erledigt zu speichern.
- Abschließende vollständige App-Suite: 175 Swift-Testing-Tests in 13 Suites erfolgreich.
  Live-Bildschirmaufnahme/globales Escape sind mangels Testhost-Freigaben
  übersprungen; der opt-in Live-Modell-Download wurde nicht gestartet.
- Release-Build mit `CODE_SIGNING_ALLOWED=NO`: **BUILD SUCCEEDED**.
  `scripts/check-localization.py` und `git diff --check`: erfolgreich.
- Echter UI-Prozessneustart: Einrichtung an derselben Stelle geöffnet; „Später“
  verhindert automatisches Wiederöffnen. Erfolgreich.
- Echter UI-Test: beide Kurzbefehle ändern, Fn ausschalten, App beenden und neu
  starten; Schritt und alle drei Einstellungen bleiben erhalten. Erfolgreich.
- Ein UI-Lauf fand einen AppKit/SwiftUI-Layoutabsturz beim Seitenwechsel. Die
  automatische Fenstervergrößerung wurde durch einen festen Rahmen mit
  scrollbarem Inhalt ersetzt; die anschließenden Navigationstests bestanden.
- Der UI-Test der Downloadbestätigung bleibt offen. Mehrere Läufe wurden durch
  das vordergründige Codex-Fenster unterbrochen; die exportierte XCTest-
  Bildschirmaufzeichnung zeigt Codex statt der Einrichtung während der Klicks.
  Daraus folgt kein Nachweis für einen funktionierenden oder defekten Dialog.
  Weitere Klickversuche wurden beendet, um die laufende Benutzerarbeit nicht zu stören.
- Layoutnachweise verwenden simulierte Freigaben und kleine Modell-Metadaten-
  Fixtures. Sie belegen die Darstellung, keine echte Systemfreigabe.

## Grenzen

Kein vollständiger Download großer Modellgewichte in diesem Arbeitsgang.
Dateidownload, SHA-256-Prüfung, Abbruch, Fehler und Auswahlwechsel sind mit kleinen
Testdateien geprüft. Der UI-Downloadtest ist nur auf Bestätigung/Abbruch des Dialogs ausgelegt
und startet kein Netz; er wurde nicht erfolgreich abgeschlossen. Kein Zurücksetzen bestehender TCC-Berechtigungen,
kein signiertes Distributionsartefakt, keine Installation nach `/Applications`,
kein Commit oder Push.

Die ursprüngliche Freigabe-Neustartprüfung ist separat in
[resumable-setup-verification.md](resumable-setup-verification.md) dokumentiert.

Lokale Nachweise: `/tmp/saywing-setup-app-final.log`,
`/tmp/saywing-setup-ui-final.log`, `/tmp/saywing-setup-ui-remaining.log`,
`/tmp/saywing-setup-download-ui.log`, `/tmp/saywing-expanded-setup-en/`,
`/tmp/saywing-expanded-setup-de/`, `/tmp/saywing-setup-release-final.log`.

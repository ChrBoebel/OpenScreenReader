# Privater Test auf einem zweiten Mac

Noch keine öffentliche Freigabe. Verwende nur den ausdrücklich benannten,
notarisierten Kandidaten mit passender Architektur und SHA-256. Ältere Kandidaten
in `rc-portable-arm64` und `rc-portable-x86_64` wurden wegen eines SDK-Problems
zurückgezogen. Der korrigierte Stand ist Version 0.1.4, Build 7, Verzeichnis `-v2`.
Die aktuelle Notarisierung und Paketprüfung stehen in `release-candidate-2026-10-15.md`.

## Testdownload über die Website

Der Eigentümer hat einen passwortgeschützten Testzugang freigegeben. Für den
M4-Mac ist die Adresse:
https://www.christopherboebel.com/downloads/saywing/private/arm64

Der Browser fragt nach Benutzername und Passwort; die Zugangsdaten werden direkt
im Chat übergeben und stehen nicht im Repository. Die öffentliche Downloadtaste
bleibt absichtlich deaktiviert. Es gibt noch keinen öffentlichen Release und
keinen aktivierten Update-Feed. Build 7 für ARM und Intel ist inzwischen von Apple
akzeptiert, das DMG-Ticket validiert und die enthaltene App durch Gatekeeper geprüft.
Der private Website-Test bietet zunächst nur ARM an. Kein Umgehen von Gatekeeper
ist erforderlich. Vor dem Start eine andere laufende Saywing-Kopie beenden.

## Welcher Mac?

Unter Apple-Menü → Über diesen Mac notieren:

- genaue macOS-Version;
- Chip/Prozessor (etwa Apple M4 oder Intel Core i5);
- Arbeitsspeicher.

Dein M4-Mac kann den frischen Apple-Silicon-Test abdecken. Für das Ziel macOS 14
fehlen zusätzlich ein tatsächlich unter macOS 14 laufender Apple-Silicon-Mac
und ein unterstützter Intel-Mac. Rosetta auf Apple Silicon ersetzt den Intel-Test
nicht. Die bisherigen Tests laufen auf macOS 26.6.2; Binärdateien wurden auf
Mindestversion und SDK geprüft, aber noch nicht unter macOS 14 ausgeführt.

## Vorbereiten

1. Neues lokales macOS-Benutzerkonto ohne Saywing-Daten und Entwicklungswerkzeuge.
2. Nur das zum Chip passende private Paket verwenden. Downloadquelle, Dateiname
   und SHA-256 im Ergebnis festhalten. Noch keine öffentliche URL verwenden.
3. DMG öffnen, Saywing nach Programme ziehen, aus Programme starten.
4. Keine Gatekeeper-Ausnahme erzwingen und keine Sicherheitsfunktion abschalten.
   Falls macOS den Start ablehnt, den exakten Meldungstext notieren und stoppen.
5. Erste Berechtigungsdialoge prüfen. Mikrofon darf beim Start nicht aufnehmen;
   Bildschirmzugriff wird erst für ausdrücklich gestartetes Vorlesen verwendet.

## Vorlesen

- Einen kurzen, nicht vertraulichen deutschen und englischen Text auswählen.
- Auswahl → Texterkennung → automatische lokale Sprache prüfen.
- Einen längeren Absatz vorlesen: keine hörbaren Lücken, keine Wiederholungen.
- Während Sprache/Modellvorbereitung mit Esc und Stop abbrechen; keine späteren
  Audiostücke. Eine weitere Auswahl während Wiedergabe wird eingereiht.
- Pause, Fortsetzen, Tempo und Pegelmesser prüfen.
- Zwischenablage vor/nach dem Lesen vergleichen: unverändert.

Intel ist besonders wichtig: Auf diesem Apple-Silicon-Testhost zeigte der Intel-
Worker unter Rosetta eine kurze Audiolücke. Stabile Intel-Wiedergabe ist noch eine
Freigabesperre; bitte auch längere Absätze und normale parallele Nutzung prüfen.

## Diktieren

- Mikrofonzugriff zunächst ablehnen: verständliche Meldung, keine Aufnahme.
- Zugriff erlauben; erst mit bewusstem Start aufnehmen.
- Standardmodell Whisper Turbo mit deutschem und englischem öffentlichem Testsatz.
- In einem einfachen Textfeld einfügen; neue Zwischenablage-Kopien während des
  Einfügens dürfen nicht mit dem alten Inhalt überschrieben werden.
- Während Aufnahme und Erkennung abbrechen: kein später eingefügter Text.
- Auf Intel müssen Qwen und Whisper Large als nicht verfügbar erscheinen; keine
  inkompatiblen Downloads. Ihre Unterstützung ist noch nicht implementiert.
- Auf ARM sind optionale Downloads nur nach ausdrücklicher Bestätigung zulässig;
  diese beiden Modelle brauchen mit der neuen Runtime noch eigene Tests.

## Offline und Updates

- Nach dem ersten lokalen Start Netzwerk abschalten und beide Standardfunktionen
  erneut testen. Die Standardmodelle müssen im Paket liegen; keine Nachinstallation.
- Keine dauerhafte Screenshot-, Text- oder Audiodatei aus den Sitzungen erwarten.
- Update-Test A → B erst mit den dafür bereitgestellten privaten Testpaketen und
  Feed durchführen. Architekturzuordnung, Abbruch und Start der aktualisierten
  App sind noch offen. Der Produktionsfeed wird hierfür nicht freigeschaltet.

## Ergebnis zurückmelden

Mac/Chip, macOS-Version, getestete Datei/Build, bestandene Schritte und genaue
Fehlermeldung nennen. Keine vertraulichen Bildschirmtexte oder Aufnahmen senden.
Eine erfolgreiche Installation allein schließt die übrigen Freigabepunkte nicht.

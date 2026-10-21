# Meeting-Mitschrift: Stimmen und PDF — Prüfprotokoll

Stand 2026-10-18, Branch `codex/meeting-speakers-pdf` (von `main` 9f9a187). Auftrag des Eigentümers: „okey setze das bitte um“ auf den Vorschlag, die Stimmen der anderen zu unterscheiden und das Transkript als PDF zu exportieren. Entscheidung: [ADR 0007](decisions/0007-meeting-speakers-and-pdf.md).

## Umgesetzt

- **PDF-Export:**
  - Der Sichern-Dialog hat das Menü „Format:“ mit PDF (vorgewählt), Markdown und reinem Text.
  - Das PDF ist A4, nummeriert und getaggt (Überschrift, Absätze).
  - Die Dokumentinfo enthält nur den Titel und „Saywing“.
- **Stimmen:**
  - Jedes Wort von „Andere“ geht an die Stimme, die in seiner Zeit am meisten sprach; ein Stimmwechsel teilt das Segment.
  - Die Stimmen heißen „Person 1“, „Person 2“ … und lassen sich umbenennen und zusammenführen.
  - Ohne Modell bleibt es bei „Andere“.
- **Pipeline:**
  - Der `MeetingVoiceTracker` speist „Andere“ auf eigener Queue in einen Diarizer und legt dessen Spannen über Anker auf die Meeting-Zeitachse.
  - Bei mehr als 5 s Rückstand wird Audio verworfen statt gestaut.
- **Auslieferung:**
  - Das LS-EEND-Modell ist mit Revision, Größe und SHA-256 je Datei gepinnt (`Runtime/Diarization/ls-eend-manifest.json`).
  - `fetch-diarization-model.py` lädt es zur Build-Zeit und prüft es.
  - `bundle-diarization-model.py` legt es nach Prüfung in die App; `release.py --diarization-model` ruft das auf.
  - Gewichte liegen nicht im Git.

## Nicht umgesetzt: der Adapter auf das Modell

Der Baustein, der FluidAudios `LSEENDDiarizer` hinter `MeetingVoiceDiarizing` setzt, fehlt. Der Grund: Das Bauen und Ausführen von FluidAudio-Code (Commit `2d6c42ca5f3accc0faf9fee9e0fff5b9b2cf6042`, der erste mit dem Trait `Diarizer`) wurde in der Agentensitzung vom Freigabe-Klassifikator blockiert. Das wurde nicht umgangen.

Bis zur Freigabe liefert `makeVoiceDiarizer` keinen Diarizer, die App zeigt also weiter „Andere“. Genauigkeit und Rechenlast des echten Modells sind deshalb **nicht gemessen**.

## Ausgeführte Prüfungen

- **Neue Suites:**
  - `MeetingExportTests` (9)
  - `MeetingVoiceTests` (12)
  - `MeetingVoiceTrackerTests` (4)
  - `MeetingVoiceControllerTests` (5)
  - `MeetingVoiceModelTests` (1)
  - ein neuer Speicher-Test in `MeetingControllerTests`
- **Ende-zu-Ende ohne Mikrofon-Hardware und ohne Stimmmodell** (`threeVoicesReachThePDFWithTheirNames`):
  - Drei synthetische deutsche Stimmen (`say`) laufen durch Controller, Apples `SpeechTranscriber`, Router und Voice-Tracker. Ein Diarizer, der weiß, wer wann sprach, ersetzt das Modell und meldet live.
  - Ergebnis: drei Beiträge mit den Stimmen 10/20/30 als „Speaker 1/2/3“.
  - Nach dem Umbenennen steht „Ben“ im gesicherten PDF; „Speaker 2“ fehlt dort, die Reihenfolge stimmt.
  - Laufzeit 2,0 s.
  - Apples Erkennung verstand bei der Stimme „Grandpa“ das Wort „Budget“ nicht. Der Test prüft daher stabile Wörter.
- **Gesamtsuite** `OpenScreenReaderAppTests`: **271 Tests in 29 Suites bestanden**, 0 fehlgeschlagen.
  - Übersprungen wurden 2 XCTest, weil dem Test-Host die Freigaben für Bildschirmaufnahme und Eingabeüberwachung fehlen (unverändert), und `liveInstallFromHuggingFace` (Opt-in).
  - Danach bestand der zusätzliche Test des Formatmenüs (9/9 in `MeetingExportTests`).
- **Release-Build** (arm64, ohne Signatur): **BUILD SUCCEEDED**, keine Warnungen in den Meeting-Dateien.
- `scripts/check-localization.py`: bestanden. Alle neuen Texte sind deutsch; die Stimmen heißen „Person 1“ usw., die Beteiligten im PDF „Beteiligte“.
- **Modell-Skripte:**
  - Alle 4 Varianten wurden geladen. Die SHA-256 der Gewichte stimmen mit den LFS-Kennungen der gepinnten Revision überein.
  - `bundle-diarization-model.py` an einer Test-App: Kopie korrekt; eine zweite Ausführung wird abgelehnt; eine manipulierte Datei lässt die Prüfung scheitern.
- **Sichtprüfung** (opt-in `MeetingPreviewTests`, hell und dunkel):
  - Live und Fertig zeigen Farbmarke, Name oder Nummer und den Menüpfeil.
  - Nach dem Umbenennen erscheint „Anna“.
  - Die erste PDF-Seite wurde gerendert und angesehen. Die Seitenzahl war zuerst fast unsichtbar (dynamische Systemfarbe im PDF-Kontext); sie hat jetzt eine feste Farbe.

## Nicht geprüft / offen

- **UI-Tests:**
  - `xcodebuild test -only-testing:OpenScreenReaderUITests` blieb bei „Setting up automation session“ stehen. macOS verlangt dafür eine Bestätigung am Gerät.
  - Der neue `testMeetingTranscriptOpensAtTheConsentStepAndCancels` kompiliert, lief aber nicht.
- **Sichern-Dialog am Gerät:** Formatwechsel, Dateiendung und Öffnen des PDFs in Vorschau und mit VoiceOver.
- **Echtes Modell:** Variante (AMI / CALLHOME / DIHARD III), Fehlzuordnungen, Latenz der Etiketten, CPU und Speicher über 60/120 min. Das sind alles Gates aus ADR 0007.
- **Echter Call** mit Systemaudio-Tap: unverändert offen aus dem [Prüfprotokoll der Mitschrift](meeting-transcript-verification.md).

## So prüft der Eigentümer am Gerät

1. Die UI-Automatisierung bestätigen, dann `xcodebuild test -only-testing:OpenScreenReaderUITests/MenuBarSmokeUITests/testMeetingTranscriptOpensAtTheConsentStepAndCancels` ausführen.
2. Eine Mitschrift aufnehmen, stoppen, **Sichern …** wählen. Das Formatmenü zeigt PDF; ein Wechsel auf Markdown ändert die Endung. Das PDF in Vorschau öffnen und mit VoiceOver lesen.
3. Nach der Freigabe für FluidAudio: Modell laden (`scripts/fetch-diarization-model.py .build/models/ls-eend`) und bündeln (`scripts/bundle-diarization-model.py <Saywing.app> .build/models/ls-eend`, vor dem Signieren). Dann einen Call mit mehreren Teilnehmenden mitschreiben.

## Lokale Installation 2026-10-19

Auf Wunsch des Eigentümers wurde der Branch (Stand 73296e1, PR #16) lokal installiert:

- **Build:** Release-Build arm64.
- **Laufzeiten:** Diktat- und Sprachlaufzeit samt Modellen wurden unverändert aus der bisherigen App übernommen. Gegenüber `main` sind `Runtime/Dictation` und `Runtime/Supertonic` unverändert.
- **Signatur:** wie am 2026-10-16 ad hoc, mit `Saywing.entitlements`, ohne Hardened Runtime. `Sparkle.framework` ist ebenfalls ad hoc signiert.
- **Prüfungen:** `codesign --verify --deep --strict` und `verify-app-permissions.py` bestanden. Die deutschen Texte für Formatmenü und Stimmen sind im Bundle.
- **Ohne Stimmmodell:** Das Stimmmodell ist nicht gebündelt, weil der Adapter fehlt. Die Stimmen der anderen bleiben deshalb „Andere“.
- **Rückfallkopie:** Die bisherige App (0.1.0, Build vom 2026-10-16) liegt unter `.build/previous-before-speakers/Saywing.app` im Worktree.
- **Nicht geprüft:** Gestartet wurde die App aus der Agentensitzung nicht, weil die Sandbox Launch Services sperrt.

## Echo bei „Ich“ — 2026-10-21

**Befund des Eigentümers** (Call über Laptop-Lautsprecher): Unter „Ich“ standen verstümmelte Kopien dessen, was „Andere“ gesagt hatten, etwa „Auf demorfest nein, Dorf Millionär. Sender.“ zu „Auf dem Oktoberfest … Millionär … Ständer“. Zwei Ursachen:

- **Textvergleich:** Er verlangte drei identische Wörter in Folge. Das Echo wird aber nur ungefähr erkannt, deshalb griff die Regel nie.
  - Neu: Ein Segment von mir gilt als Echo, wenn mindestens drei seiner Wörter mit drei oder mehr Buchstaben vorkommen und davon 60 % wie Wörter der anderen aus demselben Moment klingen.
  - Als ähnlich gilt ein Wort, wenn es gleich ist, ein Präfix ab 4 Buchstaben teilt oder sich bei Wörtern ab 5 Buchstaben um höchstens ein Drittel der Buchstaben unterscheidet.
  - Getestet mit dem Originalausschnitt: Beide Echo-Zeilen verschwinden; „Test Test Test …“ und eine eigene Antwort zum selben Thema bleiben.
- **Signalvergleich:** Die Schwelle 0,2 war ein unkalibrierter Startwert. Gemessen mit echter synthetischer Sprache und simuliertem Raum (Direktschall, Nachhall, Hochpass, leichte Verzerrung, Rauschen):

| Situation | Median | Wert |
|---|---|---|
| Zwei verschiedene Stimmen, auch derselbe Text gleichzeitig | 0,06 | höchstens 0,085 |
| Leises, verhalltes, verzerrtes Echo | 0,22 | mindestens 0,14 |
| … mit eigener Stimme darüber | 0,17 | — |

  Die Schwelle liegt jetzt bei 0,12. Die Bedingung, dass sich die Verzögerung in mehreren Analysen wiederholt, bleibt als zweite Sicherung.
  - Neue Raumtests: Echo bei 30–250 ms Verzögerung und Faktor 0,01–0,25 wird zu 100 % gefunden, bei eigenem Sprechen darüber zu 79 %.
  - Mein eigener Satz nach dem Echo bleibt zu 0 % markiert.
  - Fremde Stimmen erreichen höchstens 0,081.

**Ergebnis:**
- Gesamtsuite: 277 Tests in 30 Suites bestanden.
- Nicht geprüft: echter Raum am Gerät. Die Simulation ersetzt keine Messung mit Laptop-Lautsprechern und -Mikrofon.

**Testumgebung:** Liegt DerivedData unter `~/Documents`, hängt der Test-Host seit heute beim Laden seiner Bibliotheken in `open()` („test runner hung before establishing connection“), vermutlich wegen des Ordnerschutzes von macOS. Mit `-derivedDataPath /tmp/…` laufen die Tests.

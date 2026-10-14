# Diktieren: Mikrofonklänge und sichtbares Freihand-Einrasten — Prüfprotokoll

Stand 2026-10-14, Branch `codex/dictation-handsfree-sounds` (von `main` c1a5b1c). Eigentümerauftrag: Freihand-Diktieren wie bei Wispr Flow recherchieren und dem Diktieren Klänge geben, die zur Marke passen und sich befriedigend anfühlen; „setze alles um, entscheide alles“.

## Recherche

- **Wispr Flow** bietet Push-to-Talk (Fn halten, loslassen fügt ein) und Freihand: Fn + Leertaste oder doppeltes Antippen innerhalb einer halben Sekunde, Beenden mit demselben Kürzel. Ein dritter schneller Tipp oder Esc verwirft. Nach dem Start ertönt ein „Ping“. Nach 19 Minuten folgt eine Warnung, nach 20 Minuten endet die Aufnahme und wird trotzdem transkribiert ([Use Flow hands-free](https://docs.wisprflow.ai/articles/6391241694-use-flow-hands-free), [Shortcuts](https://docs.wisprflow.ai/articles/2612050838-supported-unsupported-keyboard-hotkey-shortcuts)).
- **Superwhisper** legt beides auf eine Taste: halten heißt Push-to-Talk, kurz tippen schaltet um. Start- und Stoppklang sind getrennt regelbar und abschaltbar ([Keyboard Shortcuts](https://superwhisper.com/docs/get-started/settings-shortcuts)).
- **Earcon-Leitlinien** ([Google](https://developers.google.com/assistant/conversation-design/earcons)): wenige, gut unterscheidbare Klänge, konsequent eingesetzt, passend zur Marke, so kurz wie möglich.
- **Apple-Design-Skill** ([emilkowalski/skills](https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md)): Ursache, Gleichklang (Bild und Ton im selben Frame), Nutzen. Reaktion beim Drücken, nicht beim Loslassen.

**Befund im Code:** Saywing hatte die Freihand-Gesten schon (`FnDictationGesture`: Fn doppelt, Fn + Leertaste, dritter Tipp verwirft). Das Einrasten war aber weder sicht- noch hörbar; nur ein Text im Testfenster änderte sich. Das Diktieren war bis auf den Abschluss-/Achtungsklang nach dem Einfügen stumm.

## Entscheidungen

| Thema | Entscheidung | Grund |
|---|---|---|
| Gesten | unverändert (halten, doppelt, Fn + Leertaste, ⌥⇧Leertaste) | entspricht Wispr; einmal Tippen als Umschalter (Superwhisper) würde versehentliche Fn-/Globus-Tipps zu Aufnahmen machen |
| Mikrofon an | C4-Marimba-Schlag, kleiner steigender Tropfen, 420 ms, Spitze 0,30 | erklingt beim Drücken mit der Kapsel; nimmt die Grundtöne des Öffnungsklangs auf |
| Freihand eingerastet | G4, eine Quinte darüber, 400 ms, Spitze 0,28 | auf „an“ folgend eine steigende Quinte: „rastet ein“ |
| Mikrofon aus | gedämpftes G3 ohne Wasser, 400 ms, Spitze 0,28 | dunkel und geschlossen; fällt nicht zweimal, damit es nie wie „Achtung“ klingt |
| Start mit ⌥⇧Leertaste / Aufnahmetaste | nur der Einrast-Klang, Kapsel sofort freihändig | ein Klang pro Ereignis, keine Stapel |
| Verwerfen | stumm, laufender Klang endet sofort | wie Stoppen beim Vorlesen |
| Übergang zwischen Klängen | 30 ms Ausblendung statt harter Schnitt | kein Knacken bei „an“ → „eingerastet“ |
| Sichtbares Einrasten | Beenden-Taste füllt sich mintfarben und rastet einmal kritisch gedämpft (86 → 100 %) ein | Markenregel: kein Text, kein Timer, kein Leuchtring während der Aufnahme |
| Einfügen bestätigt | 150 ms nach dem Einfügen zurücklesen; Häkchen und Abschlussklang kommen mit dem Text | vorher kam beides erst nach der Zwischenablage-Wartezeit von 1 s; die Wiederherstellung wartet weiterhin 1 s bzw. 2 s |
| Höchstdauer | bleibt 60 s | eine längere Grenze braucht Messungen mit den echten Modellen; siehe offene Punkte |
| Einstellung | bestehender Schalter „Interface sounds“ und Lautstärke | ein Klangschalter für die ganze App |

## Ausgeführte Prüfungen

- `xcodebuild … build-for-testing` (Debug, arm64): **TEST BUILD SUCCEEDED**, keine Warnungen in den geänderten Dateien.
- `xcodebuild -configuration Release … build` (arm64): **BUILD SUCCEEDED**.
- Komplette `OpenScreenReaderAppTests` vor der letzten Klangkorrektur: 183 bestanden, 2 fehlgeschlagen, 3 übersprungen. Ein Fehler war der neue Test `microphoneCuesAreShortQuietAndFrontLoaded`: „Mikrofon an“ hatte nur 82 % seiner Energie in den ersten 150 ms. Daraufhin wurde das Abklingen von 0,16 auf 0,12 s verkürzt. Der zweite Fehler war `draggingSurvivesSpeechTransitionsButNeverSurvivesHide` (Ziehen der Lesekapsel, nicht verändert). Danach liefen `ReadingPanelTests` und `FeedbackAtSourceTests` zusammen: **37/37 bestanden**, auch der Ziehen-Test. Danach lief die komplette Suite erneut: **185 bestanden, 0 fehlgeschlagen, 3 übersprungen** (`** TEST SUCCEEDED **`).
- Neue bzw. geänderte Tests:
  - `heldRecordingOpensLatchesAndClosesWithItsOwnCues`: Reihenfolge an → eingerastet → aus. Ein zweites Einrasten bleibt stumm. Der Schlussklang kommt erst nach `finish()` des Rekorders. Die Beenden-Taste ist hervorgehoben.
  - `handsFreeStartUsesOneCueAndDiscardingIsSilent`: ein Klang beim freihändigen Start; Verwerfen stoppt den Klang und fügt keinen hinzu.
  - `confirmedPasteSoundsWithTheTextNotAfterTheClipboardWait`: nach 400 ms Häkchen und genau ein Abschlussklang, Phase noch „pasting“; nach der Wartezeit kein zweiter Klang.
  - `handsFreeShowsOnlyOnTheFinishControlWhileRecording`: nur während einer Aufnahme, VoiceOver-Label „Recording hands-free“, keine zusätzlichen Elemente; Zurücksetzen bei der Erkennung.
  - `microphoneCuesAreShortQuietAndFrontLoaded`: unter 450 ms, leiser als Öffnen und Abschluss, eine Voicing, mehr als 85 % der Energie in den ersten 150 ms, untereinander verschieden.
  - `stopButtonPressIsSilentAndCuesKeepToMeaningfulMoments`: Liste aller Klänge erweitert.
- Klangexport über `TEST_RUNNER_OSR_PANEL_PREVIEW_DIR` (`ReadingPanelTests/exportReadingControlPreview`) und Messung mit NumPy:

| Klang | Dauer | Spitze | Spektraler Schwerpunkt | Energie in den ersten 150 ms | 90 % der Energie nach |
|---|---|---|---|---|---|
| Mikrofon an (`listening`) | 420 ms | 0,30 | 288 Hz | 90 % | 152 ms |
| Freihand (`handsFree`) | 400 ms | 0,28 | 412 Hz | 86 % | 173 ms |
| Mikrofon aus (`captured`) | 400 ms | 0,28 | 195 Hz | 91 % | 145 ms |
| zum Vergleich: Öffnen | 900 ms | 0,50 | 255 Hz | 29 % | 627 ms |
| zum Vergleich: Abschluss | 1000 ms | 0,36 | 212 Hz | 44 % | 595 ms |

## Nicht geprüft / offen

- **Anhören am Gerät:** Die Klänge sind gemessen, aber noch von niemandem angehört. Das muss der Eigentümer über Laptop-Lautsprecher und Kopfhörer tun, auch mit AirPods, die beim Öffnen des Mikrofons ins Headset-Profil wechseln.
- **Übersprechen ins Mikrofon:** „Mikrofon an“ und „eingerastet“ erklingen, während das Mikrofon schon offen ist. Über Lautsprecher kann der kurze Klang in den ersten etwa 150 ms der Aufnahme landen. Der Versuch, das mit Whisper Turbo und Qwen3-ASR zu messen, wurde in dieser Umgebung blockiert: MLX braucht Metal, und der GPU-Zugriff außerhalb der Sandbox wurde abgelehnt. Es gibt deshalb keine Behauptung über die Auswirkung auf die Erkennung. Falls nötig: die ersten 150 ms nach dem Startklang dämpfen oder den Klang vor dem Start der Audio-Engine abspielen.
- **Längere Freihand-Aufnahmen:** Die 60 s gelten weiter an mehreren Stellen: `AudioAccumulator`, `worker.py` (`decode_request`, `MAX_LINE`), Qwen `max_tokens=1024`, Zeitlimit von 90 s für die Erkennung und die Texte im Testfenster. Eine Erhöhung braucht Messungen von Laufzeit und Speicher mit den echten Modellen. Zusätzlich sollte die App auf 16 kHz heruntersampeln, bevor sie Audio an den Worker schickt, sonst wird die Pipe bei 48 kHz zu groß. Eine Warnung kurz vor der Grenze, wie bei Wispr, fehlt ebenfalls.
- **UI-Tests** wurden nicht ausgeführt, weil der Automationsmodus eine Bestätigung am Gerät verlangt.
- **Echte Fn-Gesten mit Mikrofon** wurden nicht von Hand durchgespielt. Die Tests treiben den Controller über `handle(_:)` und einen Rekorder-Ersatz; `FnDictationGesture` selbst ist unverändert.

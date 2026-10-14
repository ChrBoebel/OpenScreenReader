# Whisper Turbo als Standard und eigenes Vokabular — Verifikation 2026-10-14

Auf Wunsch des Eigentümers ist Whisper Turbo das Standardmodell fürs Diktieren.
Eine gespeicherte Modellwahl bleibt erhalten. Neu ist ein lokales Vokabular unter
Einstellungen → Diktieren. Es braucht kein neues Modell und keinen Download: Whisper
Turbo war bereits gepinnt gebündelt ([Herkunft und Lizenz](research/whisper-turbo-dictation.md)).

## Verhalten

- Ohne gespeicherte Wahl startet `whisper-turbo`; es steht im Auswahlfeld an erster Stelle.
- Vokabular: ein Begriff pro Zeile oder durch Komma getrennt, höchstens 50 Begriffe zu
  je 60 Zeichen. Leere Einträge, Duplikate und Steuerzeichen werden verworfen.
- Whisper erhält `initial_prompt` = „A, B, C.“, gekürzt auf das Prompt-Budget
  (`n_text_ctx // 2 - 1` Tokens), damit vordere Begriffe erhalten bleiben. Qwen3-ASR
  erhält `hotwords`.
- Schutzregel: Liefert die Erkennung mit Vokabular eine Wiederholungsschleife
  (zlib-Kompressionsverhältnis > 2,4 bei mehr als 40 Byte) oder nur Begriffe aus der
  Liste (mindestens drei), dekodiert derselbe Worker die Aufnahme einmal ohne Vokabular.

## Messung

`scripts/evaluate-dictation-vocabulary.py` erzeugt deutsche Sätze mit drei lokalen
macOS-Stimmen (Anna, Eddy, Flo) und ruft `load_transcriber` des Workers auf. Das
Vokabular umfasst 10 Begriffe, darunter Saywing, Böbel, Qwen, OpenRAIL-M und
Wojciechowski. Es gibt 30 Zielbegriffe in 24 Sätzen, 9 Kontrollsätze ohne Begriffe
und 5 Rauschproben.

| Modell | Sprache | Treffer ohne → mit | Kontrollsätze verändert | Schleifen übrig |
|---|---|---|---|---|
| Whisper Turbo | Automatisch | 10/30 → 26/30 | 0/9 | 0/5 |
| Whisper Turbo | Deutsch | 10/30 → 26/30 | 0/9 | 0/5 |
| Qwen3-ASR | Automatisch | 6/30 → 25/30 | 2/9 | 0/5 |
| Qwen3-ASR | Deutsch | 5/30 → 25/30 | 0/9 | 0/5 |

Vorab wurden Prompt-Formate verglichen:

- **„A, B, C“ ohne Schlusspunkt:** Whisper ließ in 22 von 33 Sätzen den Satzpunkt weg.
- **Präfix „Glossar: …“:** Das Wort „Glossar“ erschien im Text, und es entstanden
  Schleifen, die die Schutzregel nicht erkannte.
- **„A, B, C.“:** keine dieser Nebenwirkungen.

Ohne Schutzregel erzeugte Whisper mit Vokabular bei Rauschen in bis zu 10 von 10
Fällen Schleifen wie „KENG, WELCOME, WELCOME, …“. Mit Schutzregel blieb keine übrig.

Weitere Prüfungen:

- Worker-Unit-Tests: 17 bestanden.
- Echte Worker-Integration im Offline-Sandbox-Profil: je 12 Prüfungen für Whisper
  Turbo und Qwen3-ASR bestanden. Neu darunter: Eine Anfrage mit Vokabular liefert das
  Transkript, und fehlerhaftes Vokabular wird abgewiesen, ohne den Worker zu beenden.
  Für den Test lagen der neue `worker.py` und die Manifeste neben Symlinks auf die
  Modelle und Laufzeit der installierten App.
- Swift: 151 App-Unit-Tests bestanden (ohne UI-Tests), dazu 15 Core-Checks.
  Der Release-Build gelang.

## Grenzen

- Synthetische Stimmen sind nur ein Ersatz. Mit echten eigenen Aufnahmen ist das noch
  nicht gemessen.
- Whisper Turbo macht aus reinem Rauschen auch **ohne** Vokabular „Vielen Dank.“
  oder „Thank you.“. Mit Vokabular wurde daraus einmal „Konec.“. Das bestand schon
  vorher, wird aber wichtiger, weil Whisper jetzt Standard ist. Es braucht eine
  eigene Lösung, etwa eine Sprachaktivitätserkennung.
- Ein Diktat, das nur aus drei oder mehr Listenbegriffen besteht, wird als Echo
  gewertet und ohne Vokabular neu erkannt.
- UI-Tests sind nicht gelaufen. Das Einstellungsfeld wurde nicht live angesehen. Das
  installierte `/Applications/Saywing.app` enthält die Änderung erst nach einem neuen
  Build und erneutem Bündeln.

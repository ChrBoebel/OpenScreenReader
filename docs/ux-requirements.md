# UX requirements

## Primärer Ablauf

Update 2026-09-09: Der Eigentümer hat Pause/Fortsetzen, eine bearbeitbare Warteschlange und Einrichtung freigegeben. Die Kapsel bleibt textfrei; ihre kleine ···/+N-Taste öffnet eine native Steuerungsansicht mit Pause/Fortsetzen, Tempo, Weiter und wartenden Texten. Erst dieser explizite Klick zeigt maximal 100 Zeichen pro Eintrag. Entfernen, Nach-oben/-unten und Jetzt-lesen verwenden stabile Eintrags-IDs, nicht veraltete Indizes. Esc/Stop beendet auch eine Pause. Frühere Aussagen „keine Vorschau“/„Pause außerhalb“ gelten für die geschlossene Kapsel, nicht für diese neue explizite Ansicht.

Die Einrichtung erscheint beim ersten Anzeigen des Menüleistenelements und ist später über „Set Up & Test…“ erreichbar. Freigaben werden nur auf Klick angefragt. Seit 2026-10-14 (Eigentümerfreigabe „klingt gut, setze das um“) ist sie ein geführter Ablauf mit einer Entscheidung pro Seite; Details unter „Geführte Einrichtung“. Eine erteilte Freigabe heißt nur „Erlaubt“; „Es funktioniert“ erscheint erst, nachdem der echte Lesetest Sprache abgespielt hat. Fehler bieten über ? direkten Zugang zur Einrichtung und zur konkreten Fehlermeldung.

1. Der Nutzer drückt einen frei konfigurierbaren globalen Hotkey.
2. Über allen Bildschirmen erscheint ein zurückhaltendes transparentes Auswahl-Overlay.
3. Der Nutzer zieht einen rechteckigen Bereich auf.
4. Beim Loslassen verschwindet das Overlay sofort.
5. Die App erfasst ausschließlich den ausgewählten Bereich.
6. Apple Vision erkennt den Text lokal, zunächst mit Fokus auf Deutsch und Englisch.
7. Der Text wird normalisiert und in kurze sprechbare Segmente geteilt.
8. Die lokale TTS beginnt automatisch; es ist kein zusätzlicher Klick notwendig.
9. Der erneut gedrückte Hotkey öffnet während Sprache/Vorbereitung eine weitere Bereichsauswahl für die Warteschlange. `Esc` oder ein expliziter Stop-Knopf stoppt OCR, Synthese, Warteschlange und Audiowiedergabe unmittelbar. Während einer bereits laufenden Auswahl/Aufnahme/OCR erzeugen weitere Tastendrücke weder Duplikate noch einen Abbruch.

Der offizielle MVP enthält ein geprüftes Standardmodell. Der Nutzer muss vor dem ersten Vorlesen kein Modell auswählen oder separat herunterladen. Modellname, Version, Quelle, installierte Größe und Lizenz bleiben in den Einstellungen einsehbar.

## Interaktionsanforderungen

- Die App lebt primär in der Menüleiste und öffnet kein permanentes Hauptfenster.
- Der Hotkey ist konfigurierbar und darf gängige Systemkürzel nicht ungefragt überschreiben.
- Der Auswahlrahmen funktioniert auf jedem Monitor und mit unterschiedlichen Skalierungen. Im MVP bleibt ein einzelner Ziehvorgang auf den Monitor begrenzt, auf dem er begonnen wurde; displayübergreifendes Zusammensetzen ist ein späterer Kandidat.
- `Esc` bricht bereits die Bereichsauswahl ab.
- Der Mauszeiger und das Overlay dürfen nicht im Screenshot erscheinen.
- Statusanzeigen für „Erkennen“, „Sprechen“ und „Gestoppt“ bleiben klein und nicht modal.
- Fehler werden verständlich und handlungsorientiert angezeigt.
- Ein leeres beziehungsweise nicht lesbares Ergebnis startet keine TTS.
- Bedienung per Tastatur und VoiceOver-Bezeichnungen wird von Beginn an berücksichtigt.

## Kleines Vorlese-Panel

- Auswahl 2026-09-22: Die Interaktionsfläche misst 136 × 44 pt (seitlich 44 × 136 pt); seit 13.10.2026 ist die sichtbare Oberfläche darin 136 × 28 pt groß. In Ruhe zeigt sie neun Wellenbalken und Stop; Hover überblendet die Welle zu Pause/Fortsetzen und ···/+N. Größe und Stop-Position bleiben unverändert. Beide sekundären Tasten haben getrennte 40 × 44 pt große Ziele, Stop 44 × 44 pt. Ab 5 pt Bewegung wird auch auf den sekundären Tasten gezogen statt geklickt; Abbruch unterdrückt ausstehende Klicks. Pause ist erst während der Wiedergabe aktiv. Bei geöffnetem Popover bleiben die Tasten sichtbar. Menü „Playback Controls…“ und VoiceOver-Aktionen bieten Zugang ohne Hover. Popover öffnen zur Bildschirmmitte. Fehlerhilfe (?) bleibt sichtbar, normale Endzustände blenden sekundäre Tasten aus. Die verworfene 160-pt-Variante und die frühere Hover-Verbreiterung mit Esc-Keycap entfallen.

- Ein nicht aktivierendes, nicht modales Panel erscheint erst nach abgeschlossener Aufnahme: „Text erkennen …“, „Vorbereiten …“, „Vorlesen“.
- Es bleibt unten mittig auf dem ausgewählten Display, innerhalb dessen nutzbarer Fläche mit Abstand zum Dock. Es folgt weder Maus noch Auswahlrechteck.
- Der Stop-Knopf und `Esc` beenden den vollständigen Auftrag. Der erneute Hotkey fügt Text hinzu, statt abzubrechen (Eigentümerentscheidung vom 2026-09-09). Kein zusätzlicher Bestätigungsklick vor dem Vorlesen.
- „Fertig“ und „Gestoppt“ bleiben 1,1 Sekunden und ziehen sich anschließend innerhalb von 240 ms zurück. „Kein Text erkannt“ und Fehler bleiben mit einem Schließen-Knopf sichtbar; Details zu Fehlern stehen im App-Menü. Ein neuer Auftrag entfernt jedes alte Panel sofort vor der Auswahl, ohne auf eine Animation zu warten.
- Vorlese-Control: sichtbare Kapsel 136 × 28 pt, transparente Interaktionsfläche 136 × 44 pt, feste Zeichenfläche 300 × 92 pt. Hover verändert die Größe nicht; Endzustände sind 100 pt breit, Hinweise vorübergehend breiter. Forest-Material, feine Mint-Kante und ein weicher Schatten entsprechen der Diktierleiste. Bernstein bleibt Hinweisen vorbehalten.
- Beide Aktivitäten verwenden neun abgerundete Mint-Balken: 2,5 pt breit, 3 pt Abstand, 2–18 pt hoch; mit sanft helleren Mint-Spitzen und dezenter Lichtstreuung bei Sprachpegel. Ihre Höhe folgt dem tatsächlichen Pegel mit schnellem Anstieg und langsamerem Ausklingen. Stille bleibt flach. Erkennen, Vorbereiten und Warten zeigen denselben Helligkeitslauf über flache Punkte. Keine künstliche Atem- oder Silbenanimation, kein vorgetäuschter Fortschritt. CADisplayLink und zeitabhängige Glättung halten die Reaktion bei unterschiedlichen Bildwiederholraten konsistent.
- Nach der Aufnahme fällt der Auswahlrahmen als Mint-Geist sichtbar in einen leuchtenden Punkt an der gespeicherten Randposition auf dem gewählten Display und springt dort zur Kapsel auf; der Öffnungsklang fällt auf die Landung. Das Flug-Fenster ist klick-durchlässig; ein neuer Auftrag oder Abbruch entfernt es sofort.
- Endzustände ersetzen die Balken durch ein gezeichnetes Symbol (Häkchen, Stop-Quadrat, Bernstein-Ring mit Ausrufezeichen), das sich selbst zeichnet. Kein zusätzlicher Puls oder Leuchtring. Die Taste wird zum Schließen-Kreuz. Hinweise zeigen zwei Worte für rund zwei Sekunden, danach nur das Symbol; Hover zeigt den Text erneut. Vollständige Titel und Details stehen immer in den Accessibility-Labels, jeder Zustandswechsel wird als VoiceOver-Ansage gepostet.
- Position: unten horizontal oder am linken/rechten Rand vertikal (92 × 300 Punkte Zeichenfläche); Symbole und die 44 × 44 Punkte große Stop-Taste bleiben aufrecht. Wellenform bzw. Statusfläche ziehen, ab 5 Punkten Bewegung folgt das Panel direkt. Seit 2026-10-14 bestimmt beim Loslassen die Wurfrichtung den Rand: Die Zeigergeschwindigkeit der letzten 100 ms wird mit Apples Abbremsrate 0,998 hochgerechnet, der nächstgelegene Rand zu diesem Punkt gewinnt. Eine Feder je Achse (Antwortzeit 0,3 s) übernimmt die Geschwindigkeit ohne Übergangskante; ruhiges Ablegen ist kritisch gedämpft, nur ein Wurf darf leicht überschwingen. Jenseits der nutzbaren Fläche gibt die Kapsel progressiv nach (Gummiband) statt hart zu stoppen. Beim Wechsel zwischen waagerecht und senkrecht formt sich die Kapsel neu; die Haptik kommt beim Einrasten. Reduce Motion überspringt diese Bewegung. Dock und Menüleiste werden durch die nutzbare Bildschirmfläche ausgespart. Rand und relativer Versatz bleiben lokal erhalten. Einstellungen bieten dieselben drei Positionen und eine Vorschau ohne OCR/TTS. Seitliche Hinweise nutzen Tooltip und VoiceOver statt gedrehten Texts.
- Zusammenhängende Bewegung: derselbe native View bleibt während des Auftrags bestehen. Beide Kapseln erscheinen mit 140-ms-Einblendung und kritisch gedämpfter Skalierung von 96 auf 100 Prozent. Größenwechsel folgen einer kritisch gedämpften Feder ohne dekoratives Überschwingen oder Verformen. Das Vorlesen zieht sich beim normalen Abschluss innerhalb von 240 ms zurück. Tasten geben direkt beim Drücken visuelle Rückmeldung, die Stop-Zielfläche bleibt 44 × 44 pt. Der Flug vom Auswahlrahmen zur Kapsel startet schnell (Ease-out, 380 ms). Abbruch beginnt sofort und wartet nie auf Bewegung.
- Bei „Bewegung reduzieren“ entfallen räumliche und laufende Animationen; die Balken stehen still, beim Öffnen bleibt nur eine kurze Einblendung. „Transparenz reduzieren“ oder „Kontrast erhöhen“ macht den Körper deckend, erhöhter Kontrast verstärkt zusätzlich die Kontur.
- Drei originale, lokal synthetisierte Stereo-Klänge (seit 2026-10-14 ohne Tasten-Tick und -Tock: Stoppen ist ein Abbruch und bleibt still) aus einer Familie aus Holz und Wasser: Marimba-Stäbe mit 1 : 4 : 10-Teiltönen, Wassertropfen als aufsteigender Blasen-Chirp, ein tiefer Log-Drum-Schlag darunter und ein kleiner synthetischer Raum. Öffnen bei der Landung (900 ms, zwei steigende Stäbe G3 → C4 mit einem Tropfen), natürlicher Abschluss (1,0 s, bewusst dezent: leiser tiefer Marimba-Grundton und drei aufsteigende Tropfen, Spitzenpegel 0,36 statt 0,5), fehlender Text/Fehler (800 ms, zwei gedämpfte fallende Holzschläge). Spektraler Schwerpunkt der Hauptklänge liegt um 250 bis 280 Hz, mit einer tragenden Mitten-Schicht für Laptop-Lautsprecher. Öffnen und Abschluss wechseln zwischen zwei Voicings. Standardmäßig aktiviert, Effektlautstärke 70 %, separat regelbar und abschaltbar über „Interface sounds“. Kein Ton beim Stoppen selbst; vor Sprachwiedergabe und bei Abbruch werden laufende Hinweisklänge gestoppt. Ton ist nie der einzige Hinweis.
- Das Panel zeigt ausschließlich Status, nie OCR-Text oder eine Vorschau. Statuswechsel und Stop-Klick dürfen den Fokus der gerade benutzten App nicht übernehmen.
- Geschwindigkeit: 0,75× bis 2× in Menü und Einstellungen, live und lokal gespeichert; Tonhöhe unverändert. Pause und Stimmenauswahl bleiben außerhalb der Kapsel.
- Zusätzliche Texte: denselben Vorlese-Hotkey erneut drücken oder „Add Screen Region to Queue…“ wählen, ohne die aktuelle Stimme zu unterbrechen. Der bisherige separate Shortcut bleibt ein optionaler Zusatz, ist aber nicht nötig. Maximal fünf wartende Texte, FIFO, dezentes +N an der Kapsel; „Next Text“ im Menü überspringt den aktuellen Text. Esc/Stop-Knopf leeren immer die vollständige Warteschlange, auch während einer Zusatz-Auswahl. Volle Warteschlangen, leere/fehlerhafte Zusätze zeigen eine Meldung, ohne die laufende Stimme zu unterbrechen. Kein Zwischenspeichern auf Platte, keine Historie. Endet die Stimme während einer Zusatz-Auswahl/OCR, wartet die App abbrechbar auf den nächsten Text.

## Performance-Ziele

- Warteschlange: Ein Sprachprozess bleibt für die Sitzung geladen. Sobald die aktuelle Synthese abgeschlossen ist, wird während der noch laufenden Wiedergabe höchstens der nächste Text vorausberechnet (maximal acht Sekunden Quell-Audio im Vorbereitungsbuffer). Eine vorbereitete Übergabe erhält 120 ms kurze Trennung, keine zusätzliche Ladeanimation oder Hinweisklänge. Spät hinzugefügte Texte können trotzdem Wartezeit benötigen. Stop/Esc löschen auch Vorbereitung und warmes Modell. Überspringen bewahrt den vorbereiteten Nachfolger; muss eine noch laufende aktuelle Synthese hart abgebrochen werden, kann ein Neustart des Workers nötig sein.

- Bei warmem Standardmodell soll der erste Audioblock möglichst in weniger als 500 ms nach abgeschlossenem OCR-Text bereitstehen. Dies ist ein Ziel, kein Nachweis für den aktuellen Supertonic-Entwicklungspfad.
- Der erste Satz wird abgespielt, während spätere Sätze noch synthetisiert werden.
- Abbruchreaktion: Zielwert unter 100 ms bis Audio verstummt.
- Das Modell wird zeitlich begrenzt warm gehalten; die genaue Dauer wird anhand von Energie- und RAM-Messungen festgelegt.
- Ein sparsamer Modus darf ein kleineres Modell verwenden.
- Die größere Installationsdatei durch das gebündelte Modell wird vor dem Download auf der Website klar angegeben.

## Texttreue

Die Pipeline benötigt Testfälle und gegebenenfalls einen Treuemodus für:

- Zahlen, Daten und Geldbeträge;
- Abkürzungen und Initialen;
- URLs und E-Mail-Adressen;
- Produktcodes und Kennziffern;
- gemischtsprachige Texte;
- OCR-Zeilenumbrüche und Trennstriche;
- Tabellen, Spalten und Quellcode.

Schöne Prosodie darf keine Wortauslassungen oder sinngemäße Umformulierungen rechtfertigen.

## Nicht im ersten MVP

- Cloud-Stimmen;
- Übersetzung;
- Zusammenfassungen oder Chat;
- Voice Cloning;
- Dokumentbibliothek;
- dauerhafte Historie;
- vollständige Screenreader-Navigation;
- Windows- oder iOS-Versionen.

## Spätere Kandidaten

- vorherigen Bereich erneut lesen;
- denselben Bereich wiederholt überwachen;
- Satz wiederholen;
- optional kopieren;
- Satz- oder Worthervorhebung;
- eigene Aussprachekorrekturen;
- zusätzliche lokale TTS-Provider.

## Diktieren — integriert nach Eigentümerfreigabe 2026-10-13

Seit 2026-10-14: Freigaben in der gemeinsamen Einrichtung („Set Up & Test…“), Modell, Sprache (Automatisch/Deutsch/English) und 1/2 s Clipboard-Restore unter Einstellungen → Diktieren, Testfenster über „Try Dictation…“ mit eigenem Testfeld; Demo-Hörproben nur in Debug-Builds. ⌥⇧Leertaste startet/beendet im zuvor fokussierten Feld; Esc verwirft. Die nicht aktivierende Statusfläche zeigt Aufnahme/Erkennung/Einfügen und bietet Verwerfen. Text erscheint nach dem Stoppen, nicht während der Aufnahme. Ein Kaltstart darf PCM begrenzt im RAM halten, bis das ausgewählte Modell bereit ist. Vorlesen endet vor Aufnahme; Start von Vorlesen verwirft Diktieren. Keine automatische Aufnahme nach Berechtigungsdialog und keine Enter-Taste zum Absenden. Geänderte Ziele behalten das Ergebnis zur manuellen Kopie im Diktierfenster. Exakte Rückleseprüfung unterscheidet „Eingefügt“ von „Einfügen ausgelöst“. Universelle Textfeld-Kompatibilität wird nicht zugesichert.

## Tastaturentscheidung 2026-10-13

Vorlesen nutzt standardmäßig **⌥R** (ausdrücklich nur zwei Tasten); Wiederholen fügt weiterhin einen weiteren Bereich zur Queue hinzu. Gespeicherte Kombinationen bleiben erhalten, einschließlich des früheren Standards ⌘⇧Y. Der Eigentümer hat anschließend ausdrücklich ⌘⇧Y für seine Installation gewählt; diese Wahl darf beim Neustart nicht überschrieben werden. Diktieren nutzt **Fn halten/loslassen**, **Fn doppelt** oder **Fn+Leertaste** für freihändig, erneutes Fn zum Abschließen sowie Esc zum Verwerfen. Einzelne kurze Fn-Tipps werden verworfen, ein dritter schneller Tipp verwirft ebenfalls. Andere Fn-Kombinationen sollen unverändert nutzbar bleiben. ⌥⇧Leertaste bleibt die Alternative ohne Fn. Fn setzt verfügbare globale Tastatursteuerung mit Bedienungshilfenfreigabe voraus.

## Auswahl des Diktiermodells — 2026-10-13

Einstellungen → Diktieren bietet Qwen3-ASR und Whisper Turbo im Feld „Modell“ an (bis 2026-10-13 im Diktierfenster).
Die Wahl bleibt nach einem Neustart erhalten. Das gewählte Modell lädt automatisch;
der Ladestatus benennt es und startet keine Aufnahme. Während eines aktiven Diktats
ist die Auswahl gesperrt. Bei einem Ladefehler bleibt die gewählte Option sichtbar,
ohne automatischen Wechsel oder Download. Sprache, Tastenkürzel und Einfügeverhalten
sind für beide Modelle gleich.

Seit 2026-10-14 steht Whisper Turbo an erster Stelle und ist ohne gespeicherte Wahl
voreingestellt. Darunter nimmt das Feld „Vokabular“ einen Namen oder Begriff pro Zeile
auf (auch durch Komma getrennt, höchstens 50). Änderungen gelten ab dem nächsten
Diktat; leere Zeilen und Duplikate werden ignoriert.

The integrated dictation capsule shares Saywing’s reading material and motion language, with distinct discard and finish/paste controls. Native states, accessibility behavior and actual verification are recorded in [dictation capsule verification](dictation-capsule-verification.md).

## Apple-Design-Verfeinerung — 2026-10-14

Freigabe durch den Eigentümer: alle Punkte des Reviews vom 14.10.2026 umsetzen.

- **Eine Sprache pro Oberfläche:** englische Quelltexte, vollständiger deutscher String Catalog, die App folgt der Systemsprache.
- **Menü:** Status zuerst; Hinweise nur, wenn sie Information hinzufügen; „Bildschirmbereich vorlesen…“ zeigt den globalen Kurzbefehl; Pause, Nächster Text, Hinzufügen und Wiedergabesteuerung erscheinen nur während des Vorlesens; Fehler bieten „Einrichtung öffnen…“.
- **Einstellungen:** Tabs Allgemein, Vorlesen, Diktieren, Kurzbefehle, Datenschutz. Kurzbefehle werden in einem Aufnahmefeld gedrückt statt über Checkboxen gebaut; der zusätzliche Warteschlangen-Kurzbefehl liegt unter „Erweitert“. Freigaben zeigen ihren Status und öffnen ihren eigenen Bereich in den Systemeinstellungen.
- **Einrichtung:** ein Ablauf für Vorlesen und Diktieren; seit 2026-10-14 als geführte Einrichtung (unten). Der frühere Hinweis, der Vorlesetest brauche nur die Bildschirmaufnahme, war falsch: Die Erfassung startet ohne Eingabeüberwachung nicht (ADR 0005).
- **Auswahl:** Leertaste verschiebt, Umschalt fixiert die zuerst unbewegte Kante, Wahl wächst von der Mitte – wie bei ⌘⇧4. Die Abdunklung blendet in 90 ms ein, Eingaben gelten sofort, das Overlay schließt weiterhin sofort. Ein kurzer Hinweis erscheint bei den ersten fünf Auswahlen.
- **Klick liest Absatz:** Ein Klick ohne Ziehen erkennt einen begrenzten Bereich (max. 1200 × 800 pt) um den Zeiger und liest nur den Absatz darunter; der Rest wird sofort verworfen. Details unter [Datenschutz](privacy.md).
- Nachweise und Grenzen: [Apple-Design-Verfeinerung](apple-design-refinements-verification.md).

## Geführte Einrichtung

Freigabe durch den Eigentümer am 2026-10-14 nach dem Vorschlag auf Basis des Apple-Design-Skills („ask at the right moment, only for what's needed“).

- **Eine Entscheidung pro Seite**, festes Fenster (500 × 560 pt). Symbol und Titel stehen auf jeder Seite an derselben Stelle. Die Hauptaktion steht rechts unten (Return), „Zurück“ links unten, „Später“/„Nicht jetzt“ ist immer gleichwertig erreichbar.
- **Reihenfolge:** Willkommen → Bildschirmaufnahme → Eingabeüberwachung → Lesetest → „Auch mit der Stimme schreiben?“ → (bei Ja) Mikrofon → Bedienungshilfen → Diktiertest → Fertig. Die Reihenfolge ergibt sich nur aus den aktuellen Freigaben. Erteilte Schritte werden übersprungen, und ein Test, der ohne seine Freigabe nur scheitern würde, entfällt. Wer wiederkommt, landet beim ersten fehlenden Schritt und nie wieder beim Willkommen. Nichts über den Fortschritt wird gespeichert.
- **Titel nach Nutzen, nicht nach Systembegriff** („Den markierten Text lesen“, „Jederzeit mit Esc stoppen“). Der Name in den Systemeinstellungen steht klein darunter, damit man ihn wiederfindet.
- **Warten auf die Systemeinstellungen:** Nach „Freigeben…“ prüft Saywing alle 300 ms, und nur solange dieser Schritt wartet. Ist die Freigabe da, zeichnet sich ein Häkchen, Saywing holt sein Fenster nach vorn und blättert nach 0,9 s weiter. Ist Bildschirmaufnahme eingeschaltet, aber noch nicht wirksam, bietet die Seite „Beenden & neu öffnen“ an; die Einrichtung setzt danach fort (`--resume-setup`).
- **Hinweis neben den Systemeinstellungen:** Solange gewartet wird und die Systemeinstellungen vorne sind, schwebt neben ihrem Fenster eine kleine Karte: „Saywing einschalten“ mit dem App-Symbol, das sich in die Liste ziehen lässt. Die Karte ist schließbar und verschwindet, sobald die Freigabe da ist.
- **Lesetest im Fenster:** Der Kurzbefehl wird als Taste gezeigt, darunter steht ein eigener Beispielsatz. Der Nutzer zieht wie gewohnt einen Rahmen darum; die echte Pipeline liest vor. Das Einrichtungsfenster ist das einzige eigene Fenster, das die Erfassung lesen darf, damit kein privater Bildschirminhalt nötig ist. Esc während des Vorlesens zählt als Erfolg.
- **Diktieren** wird angeboten, nicht verlangt. Der Test nutzt das vorhandene Diktier-Testfeld.
- **Fertig** zeigt die Menüleiste mit hervorgehobenem Saywing-Symbol, und unter dem echten Menüleistensymbol erscheint „Hier wohnt Saywing“, denn die App hat kein Dock-Symbol. Fehlende Freigaben stehen dort mit je einer Aktion.
- **Rechtzeitig fragen:** Fehlt eine Lese-Freigabe, öffnet der Kurzbefehl direkt die Einrichtung, statt erst eine Auswahl zu ermöglichen, die danach scheitert. Der Diktierhinweis „Einrichtung öffnen…“ springt direkt zu den Diktier-Schritten.
- **Bewegung:** Die neue Seite gleitet aus der Bewegungsrichtung herein, kritisch gedämpft (`response 0,35`, ohne Überschwingen); die alte blendet aus. Bei reduzierter Bewegung gibt es nur eine Überblendung, das Häkchen erscheint dann ohne Zeichnen. Jeder Seiten- und Ergebniswechsel wird für VoiceOver angesagt.
- Nachweise und Grenzen: [Geführte Einrichtung — Verifikation](guided-setup-verification.md).

## Rückmeldung am Ort des Geschehens

Freigabe durch den Eigentümer am 2026-10-14 („setze das alles um“) nach dem dritten Review mit dem Apple-Design-Skill.

- **Fehlerhilfe an der Kapsel:** Nach einem Fehler öffnet das „?“ der Lesekapsel ein Popover direkt an der Kapsel, mit dem konkreten Grund und genau einem nächsten Schritt: „Erneut versuchen“, bei belegtem Kurzbefehl „Kurzbefehl-Einstellungen …“ (öffnet den Tab Kurzbefehle) und bei fehlender Freigabe „Einrichtung öffnen …“ (springt zum fehlenden Schritt).
- **Diktat am Cursor:** Die Diktierkapsel erscheint direkt unter der Einfügestelle, bei Platzmangel darüber und immer auf dem Bildschirm. Ohne ermittelbare Einfügestelle erscheint sie dort, wo der Nutzer die Lesekapsel angedockt hat. Während eines Diktats springt sie nicht.
- **Diktier-Testfenster:** ein Satz Anleitung, Status, Testfeld, Aufnehmen/Verwerfen. „Nicht eingefügt“ mit Ergebnis und Kopieren erscheint nur, wenn das Einfügen scheiterte oder nicht bestätigt wurde. Freigaben laufen über die Einrichtung.
- **Klänge beim Diktieren:** dieselben Hinweisklänge wie beim Vorlesen und dieselbe Einstellung: „fertig“ bei bestätigtem Einfügen, „Achtung“ bei unbestätigtem Einfügen oder einem Problem. Der Klang fällt mit dem sichtbaren Zustand zusammen und erklingt nie während einer Aufnahme.
- **Menüleistensymbol:** ein Punkt während des Vorlesens, ein kleines Dreieck nach einem Fehler. Der Zustand ist an der Form erkennbar, nicht an der Farbe, und das Symbol bleibt eine Vorlage. Für Aufnahmen zeigt macOS seine eigene Mikrofonanzeige.
- **Barrierefreiheit (Audit 2026-10-14):**
  - Diktat-Ergebnisse, Pause/Fortsetzen, neue Texte in der Warteschlange, das Auswahl-Overlay, Kurzbefehl-Hinweise und das Warten auf die Systemeinstellungen werden angesagt. Fehler werden mit hoher Priorität angesagt. Der Sprechbeginn und laufende Aufnahmen werden nicht angesagt, damit VoiceOver weder über die Stimme spricht noch mit aufgenommen wird.
  - Im Auswahl-Overlay liest Return den Absatz unter dem Zeiger.
  - Tab verlässt das Diktier-Testfeld.
  - Pause und Optionen der Lesekapsel sind sichtbar, solange VoiceOver oder die Schaltersteuerung aktiv ist.
  - Warteschlangen-Zeilen tragen den Text als Namen.
  - Die Kurzbefehlsfelder sind nach ihrer Aufgabe benannt und melden Änderungen.
  - Status-Texte stehen in voller Kontrastfarbe; die Farbe trägt nur das Symbol.
  - Der Auswahlrahmen hat eine dunkle Außenlinie; bei erhöhtem Kontrast ist er schwarz-weiß.
  - In der Einrichtung landet der VoiceOver-Fokus auf dem neuen Seitentitel.
  - Das Menü bietet „Fertig & einfügen“ während einer Aufnahme und „Diktieren ausprobieren …“.
  - Öffnet man die Wiedergabesteuerung über das Menü, erhält sie den Tastaturfokus; ein Klick auf die Kapsel lässt die aktive App vorne.
- Nachweise und Grenzen: [Geführte Einrichtung — Verifikation](guided-setup-verification.md#rückmeldung-am-ort-des-geschehens).


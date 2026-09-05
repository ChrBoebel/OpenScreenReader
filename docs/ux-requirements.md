# UX requirements

## Primärer Ablauf

1. Der Nutzer drückt einen frei konfigurierbaren globalen Hotkey.
2. Über allen Bildschirmen erscheint ein zurückhaltendes transparentes Auswahl-Overlay.
3. Der Nutzer zieht einen rechteckigen Bereich auf.
4. Beim Loslassen verschwindet das Overlay sofort.
5. Die App erfasst ausschließlich den ausgewählten Bereich.
6. Apple Vision erkennt den Text lokal, zunächst mit Fokus auf Deutsch und Englisch.
7. Der Text wird normalisiert und in kurze sprechbare Segmente geteilt.
8. Die lokale TTS beginnt automatisch; es ist kein zusätzlicher Klick notwendig.
9. `Esc` oder der erneut gedrückte Hotkey stoppt OCR, Synthese, Warteschlange und Audiowiedergabe unmittelbar.

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

- Ein nicht aktivierendes, nicht modales Panel erscheint erst nach abgeschlossener Aufnahme: „Text erkennen …“, „Vorbereiten …“, „Vorlesen“.
- Es bleibt unten mittig auf dem ausgewählten Display, innerhalb dessen nutzbarer Fläche mit Abstand zum Dock. Es folgt weder Maus noch Auswahlrechteck.
- Der Stop-Knopf beendet den vollständigen Auftrag. `Esc` und der erneute Hotkey bleiben unverändert verfügbar. Kein zusätzlicher Bestätigungsklick vor dem Vorlesen.
- „Fertig“ und „Gestoppt“ bleiben 1,1 Sekunden und ziehen sich anschließend innerhalb von 240 ms zurück. „Kein Text erkannt“ und Fehler bleiben mit einem Schließen-Knopf sichtbar; Details zu Fehlern stehen im App-Menü. Ein neuer Auftrag entfernt jedes alte Panel sofort vor der Auswahl, ohne auf eine Animation zu warten.
- Vorlese-Control: eine textfreie Kapsel, 44 Punkte hoch, auf einer festen 300 × 92 Punkte großen Zeichenfläche. Aktiv ist sie 136 Punkte breit (Balken links, runde 44 × 44 Punkte große Taste rechts), bei Hover 176 (Esc-Tastenkappe), in Endzuständen 100 (Symbol plus Taste), bei Hinweisen vorübergehend so breit wie zwei Worte. Sehr dunkler Körper über System-Blur mit Randlicht, Glanzkante und zwei gezeichneten Schatten; Voice Mint für Balken und Leuchten, Mint Light für Spitzen, Bernstein nur für Hinweise. Diese Kapselform und die Balken sind eine bewusste Ausnahme von der bisherigen Formregel des Markensystems.
- Neun abgerundete Mint-Balken sind die Stimme. Ihre Höhe folgt einer laufenden Welle, die vom gerenderten Sprachpegel getrieben wird (schneller Anstieg, langsames Abklingen); bei jedem Silbenkick läuft ein heller Impuls durch die Reihe, die Farbe wandert mit der Höhe von gedämpftem Mint zu Mint Light mit hellem Kern. Erkennen zeigt flache Punkte mit einem wandernden Licht, Vorbereiten lässt die Balken nacheinander aufstehen und atmen. Kein Equalizer nach Frequenz, keine Mikrofonmetapher, kein vorgetäuschter Fortschritt.
- Nach der Aufnahme fällt der Auswahlrahmen als Mint-Geist sichtbar in einen leuchtenden Punkt unten auf dem gewählten Display und springt dort zur Kapsel auf; der Öffnungsklang fällt auf die Landung. Das Flug-Fenster ist klick-durchlässig; ein neuer Auftrag oder Abbruch entfernt es sofort.
- Endzustände ersetzen die Balken durch ein gezeichnetes Symbol (Häkchen, Stop-Quadrat, Bernstein-Ring mit Ausrufezeichen), das sich selbst zeichnet; „Fertig“ bekommt einen kurzen Puls und einen nach außen laufenden Leuchtring. Die Taste wird zum Schließen-Kreuz. Hinweise zeigen zwei Worte für rund zwei Sekunden, danach nur das Symbol; Hover zeigt den Text erneut. Vollständige Titel und Details stehen immer in den Accessibility-Labels, jeder Zustandswechsel wird als VoiceOver-Ansage gepostet.
- Zusammenhängende Bewegung: derselbe native View bleibt während des Auftrags bestehen. Die Breite folgt einer Feder mit einmaligem Überschwingen, ein schnell bewegter Körper drückt sich leicht flach. Beim Schließen zieht sich die Kapsel kritisch gedämpft in den Punkt zurück und blendet innerhalb von 240 ms aus. Druck zieht den Körper zwei Prozent zusammen und legt die Balken flach; die sichtbare runde Taste komprimiert und federt zurück, ihre Hit-Area und Position bleiben. Druck und Loslassen lösen Haptik und je einen Klick aus. Abbruch beginnt sofort und wartet nie auf Bewegung.
- Bei „Bewegung reduzieren“ entfallen Flug, Feder, Wander-Licht, Silbenimpulse, Selbstzeichnen, Puls, Bloom und Druckskalierung; die Balken stehen still. „Transparenz reduzieren“ macht den Körper deckend, „Kontrast erhöhen“ verstärkt die Kontur.
- Fünf originale, lokal synthetisierte Stereo-Klänge aus einer Familie aus Holz, Glas und Atem, jeweils mit Anschlag, Sub-Fundament und kleinem synthetischem Raum: Öffnen bei der Landung (700 ms, Einatmen und steigende Quarte), natürlicher Abschluss (1,2 s, gezupftes Dur-Arpeggio mit Glocke und Oktav-Schimmer), fehlender Text/Fehler (650 ms, zwei gedämpfte fallende Klopfer), Taste gedrückt (80 ms) und losgelassen (100 ms). Öffnen und Abschluss wechseln zwischen zwei Voicings. Standardmäßig aktiviert, Effektlautstärke 70 %, separat regelbar und abschaltbar über „Interface sounds“. Kein Ton beim Stoppen selbst; vor Sprachwiedergabe und bei Abbruch werden laufende Hinweisklänge gestoppt, Tastenklicks jedoch nie abgeschnitten. Ton ist nie der einzige Hinweis.
- Das Panel zeigt ausschließlich Status, nie OCR-Text oder eine Vorschau. Statuswechsel und Stop-Klick dürfen den Fokus der gerade benutzten App nicht übernehmen.
- Pause, Geschwindigkeit und Stimmenauswahl gehören nicht in diese erste kompakte Bedienfläche.

## Performance-Ziele

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

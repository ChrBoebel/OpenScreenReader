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
- Vorlese-Control: feste Zeichenfläche 376 × 100 Punkte, sichtbarer Körper 312 × 60 Punkte mit 20-pt-Ecken (kontinuierliche Kurve) und runder 44 × 44 Punkte großer Schaltfläche rechts. Local Ink als leicht transluzente Tönung über einem System-Blur-Material, Warm Paper für Schrift und Taste, Voice Mint für Band und Leuchten, ein warmes Bernstein nur für Hinweise. Zwei gezeichnete Schatten (weich und Kontakt), oben eine feine Glanzkante. Keine neue Logo-Variante.
- Systemschrift, Titel 12,5 pt semibold, Detailzeile 10,5 pt. Links ein rund 92 pt breites Mint-Band mit Halo und radialem Leuchten: Seine Amplitude folgt dem gerenderten Sprachpegel (schneller Anstieg, langsames Abklingen), nicht der Ankunft von Synthesepaketen; in Pausen beruhigt es sich auf ein leises Atmen. Erkennen zeigt eine flache Linie mit einem wandernden Licht, Vorbereiten ein ruhiges Anschwellen ohne vorgetäuschten Fortschritt. Keine Aufnahme-/Mikrofonmetapher und kein Equalizer.
- Endzustände ersetzen das Band durch ein gezeichnetes Symbol (Häkchen, Stop-Quadrat, Bernstein-Ring mit Ausrufezeichen), das sich selbst zeichnet; der Text rückt nach links, „Fertig“ bekommt einen kurzen sanften Puls des Körpers. Die Taste wird zum Schließen-Kreuz.
- Zusammenhängende Bewegung: derselbe native View bleibt während des Auftrags bestehen. Der Körper öffnet sich aus einem 60-pt-Punkt mittig mit einer einmaligen Feder (ca. 400 ms, leichtes Überschwingen); Inhalt blendet ab etwa der Hälfte ein. Beim Schließen zieht er sich kritisch gedämpft in den Punkt zurück und blendet innerhalb von 240 ms aus. Hover hebt Kontur und Detailzeile leicht an; Druck komprimiert nur die sichtbare runde Fläche der Taste (Feder zurück), nicht deren Hit-Area oder Position, und löst Haptik und einen Tap-Klang aus. Abbruch beginnt sofort und wartet nie auf Bewegung.
- Bei „Bewegung reduzieren“ entfallen Feder, Wander-Licht, Selbstzeichnen, Puls und Druckskalierung; das Band steht still. „Transparenz reduzieren“ macht den Körper deckend, „Kontrast erhöhen“ verstärkt die Kontur.
- Vier originale, lokal synthetisierte Klänge aus einer Familie (Anschlag, harmonischer Körper, kurzer Ausklang): Öffnen nach abgeschlossener Aufnahme (420 ms, steigende Quarte), natürlicher Abschluss (760 ms, Dur-Arpeggio mit glockigem Ausklang), fehlender Text/Fehler (460 ms, zwei gedämpfte fallende Klopfer) und Tastendruck (60 ms Klick). Standardmäßig aktiviert, Effektlautstärke 60 %, separat regelbar und abschaltbar über „Interface sounds“. Kein Ton beim Stoppen selbst; vor Sprachwiedergabe und bei Abbruch werden laufende Hinweisklänge gestoppt, der Tastenklick jedoch nie abgeschnitten. Ton ist nie der einzige Hinweis. Die subjektive Klangabstimmung bleibt anhand tatsächlicher Nutzung zu bewerten.
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

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

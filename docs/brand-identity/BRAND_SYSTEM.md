# Saywing — verbindliche Markenidentität

Vom Eigentümer am **13.10.2026** ausgewählt. Dieses Dokument ersetzt frühere OpenScreenReader-/Owl-Frame-Entscheidungen. [Frühere Regeln und Prüfergebnisse](BRAND_SYSTEM_2026-09.md) bleiben als Historie erhalten.

## Name und Sprache

| | Deutsch | English |
|---|---|---|
| Name | Saywing | Saywing |
| Zusatz | Vorlesen & Diktieren für macOS. | Read aloud & dictate on your Mac. |
| Leitgedanke | Text hören. Mit der Stimme schreiben. | Hear text. Write with your voice. |
| Aktion 1 | Vorlesen — Bildschirmbereich wählen. Zuhören. | Read aloud — Select a screen region. Listen. |
| Aktion 2 | Diktieren — Sprechen. Text einfügen. | Dictate — Speak. Insert text. |

Eine native Menüleisten-App, eine Marke, zwei ausdrücklich gewählte Aktionen. Die Eule steht für Aufmerksamkeit; der Zusatz erklärt die Funktion. Schreibweise immer **Saywing**, nicht SayWing oder Saywring.

**Aktueller Funktionsstand:** experimentelles lokales Vorlesen ist implementiert. Diktieren wird separat erprobt und ist in dieser App noch nicht verfügbar. Die gemeinsame Positionierung wird immer mit „Diktieren · in Erprobung“ beziehungsweise „Dictation · in testing“ verbunden. Kein aktiver Diktierknopf, kein zugesicherter Termin und kein Versprechen, dass jedes Textfeld funktioniert.

Datenschutz bleibt eine Produkteigenschaft: kein Cloud-OCR/TTS, kein Konto, keine Standardtelemetrie und keine dauerhafte Inhaltshistorie. Expliziter Stop beendet den aktiven Vorlesevorgang. Der Vorlesepfad schreibt nicht automatisch in die Zwischenablage. Einfüge- und Datenschutzverhalten des Diktierprototyps benötigen ihre eigene Integrationsentscheidung; das Branding ändert diese Regeln nicht.

## Bildmarke und Assets

- [Flache Bildmarke](assets/saywing-logo.png): Quiet Owl in Wacholdergrün auf transparentem Grund.
- [App-Icon](assets/saywing-app-icon.png): helle Eule auf dunkelgrüner Icon-Fläche.
- [Menüleistenzeichen](assets/saywing-menubar.png): monochrome Eule mit offeneren Augen.
- [Visuelle Vorschau](saywing.html) und [maschinenlesbare Tokens](assets/brand-tokens.json).

Breite Silhouette, mandelförmige Augen, flache Stirnkerbe, kleiner integrierter Schnabel und weichere Spitzen bleiben erhalten. Kein Mikrofon, Dokument, Glitzern oder Wellenpaket in der Eule. Lautsprecher und Mikrofon erklären die Aktionen separat mit Text.

Die bestätigten Master sind transparente Rasterdesigns. Native Asset-Katalog-Exporte sind implementiert. Mathematisch exakte Vektoren und ein Icon-Composer-Layerstapel bleiben eine Produktionsverbesserung; diese Dateien sind keine Vektormaster.

## Farbe und Schrift

| Token | Wert | Anwendung |
|---|---|---|
| Juniper | `#173C33` | Logo, Wortmarke, dunkle Markenfläche |
| Porcelain | `#F2F4EF` | Heller Hintergrund und inverse Schrift |
| Leaf | `#407D65` | Dekorativer Akzent |
| Leaf Text | `#356B56` | Bedienelemente auf hellen Flächen |
| Forest | `#0C1F1A` | Dunkle Vorlesekapsel |
| Pale Leaf | `#A8D5BD` | Aktivität und Bedienelemente auf dunklen Flächen |
| Porcelain Light | `#E1EFE5` | Helle Kapselakzente |

Berechnete Kontraste: Juniper/Porcelain **10,96:1**, Pale Leaf/Forest **10,53:1**. Leaf/Porcelain hat nur **4,37:1** und wird nicht für kleine normale Schrift verwendet. Stattdessen Juniper oder Leaf Text verwenden. Auf wechselndem Bildschirminhalt garantiert eine einzelne Rahmenfarbe keinen Kontrast; Abdunklung und Auswahlgeometrie bleiben wichtig. Zustände nie ausschließlich durch Farbe vermitteln.

Schrift: native macOS-Systemschrift in der App; lokale System-Sans-Serif in der Vorschau. Keine extern geladenen Fonts. Rundum mindestens eine Augenhöhe Freiraum um die sichtbare Bildmarke. Für kleine Darstellungen das separate Menüleistenzeichen verwenden. Name und erklärender Zusatz stehen bei Erstkontakt zusammen.

## Native Umsetzung

- Buildprodukt **Saywing.app**, Programmdatei **Saywing**.
- Einstellungen und Einrichtung zeigen Namen, App-Icon, Zusatz und ehrlichen Entwicklungsstand.
- Menüleiste: Template-Eule mit vom System gewählter Hell-/Dunkelfarbe. Tooltip und zugänglicher Name enthalten den aktuellen Zustand; im Menü bleibt er sichtbar lesbar.
- Vorlesekapsel: neue Grünpalette, bestehende Interaktion, Klänge, Bewegung, Stop-Zielfläche und Accessibility-Verhalten. Amber bleibt Hinweis-/Fehlerfarbe.
- `sh scripts/export-app-icon.sh` erzeugt App-Icon-Größen und 22-pt-Menüvorlagen in 1×/2×/3× aus den bestätigten Mastern.
- Bundle-ID `com.christopherbobel.OpenScreenReader`, Einstellungsschlüssel und `Application Support/OpenScreenReader` bleiben kompatibel. Xcode-Projekt, Scheme und Swift-Module behalten technische Namen.
- Das Entwicklungspackaging verarbeitet und erzeugt Saywing.app. Die Markenumstellung lädt keine Modelle und veröffentlicht keine Pakete.

## Tonalität

Ruhig, direkt, konkret. Handlung und Ergebnis erklären. Keine unbelegten Produktivitätszahlen, autonome Aufnahmen, automatisches Senden, universelle Kompatibilität oder erfundene Nutzerstimmen versprechen.

## Noch zu validieren

[Namensrecherche](SAYWING_RESEARCH.md): vorhandener spanischer Firmenname, registrierte .com-Domain, kein .app-RDAP-Eintrag zum Prüfzeitpunkt, null TMview-Treffer für die Basisabfrage. Das ist keine rechtliche Freigabe oder Garantie der Domainverfügbarkeit.

Der Name ist vom Eigentümer ausgewählt. Ein echter Verständlichkeitstest bleibt offen; das [lokale Testblatt](name-test.html) ist vorbereitet, es wurden keine Personen befragt. Domainregistrierung, Markenanmeldung, Veröffentlichung und Outreach wurden nicht ausgeführt. Tatsächliche technische Ergebnisse stehen in [SAYWING_VERIFICATION.md](SAYWING_VERIFICATION.md).

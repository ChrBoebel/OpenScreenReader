> Historische Quiet-Owl-Identität vom 13.10.2026. Am 14.10.2026 durch [Text wird Stimme](BRAND_SYSTEM.md) ersetzt.

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

**Aktueller Funktionsstand:** lokales Vorlesen und ausdrücklich gestartetes lokales Diktieren sind im privaten Entwicklungsbuild integriert. Keine universelle Textfeld-Kompatibilität oder öffentliche Release-Reife versprechen. Modellwahl, Berechtigungen und die noch offenen Prüfungen stehen im [Diktier-Prüfprotokoll](../dictation-integration-verification.md).

Datenschutz bleibt eine Produkteigenschaft: kein Cloud-OCR/TTS/ASR, kein Konto, keine Standardtelemetrie und keine dauerhafte Inhaltshistorie. Der Vorlesepfad schreibt nicht automatisch in die Zwischenablage. Beim expliziten Diktieren wird sie zum Einfügen kurz verwendet und nur bei unveränderter Eigentümerschaft wiederhergestellt; neuere Kopien haben Vorrang. Keine Mikrofonaufnahme beim App-Start.

## Bildmarke und Assets

- [Flache Bildmarke](assets/archive/quiet-owl/saywing-logo.png): Quiet Owl in Wacholdergrün auf transparentem Grund.
- [App-Icon](assets/archive/quiet-owl/saywing-app-icon.png): helle Eule auf dunkelgrüner Icon-Fläche.
- [Menüleistenzeichen](assets/archive/quiet-owl/saywing-menubar.png): monochrome Eule mit offeneren Augen.
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
- Vorlese- und Diktierkapsel: gemeinsame Grünpalette, Oberfläche und Bewegungsregeln; eigenständige Aktionen und zugängliche Beschreibungen. Amber bleibt Hinweis-/Fehlerfarbe.
- `sh scripts/export-app-icon.sh` erzeugt App-Icon-Größen und 22-pt-Menüvorlagen in 1×/2×/3× aus den bestätigten Mastern.
- Bundle-ID `com.christopherbobel.OpenScreenReader`, Einstellungsschlüssel und `Application Support/OpenScreenReader` bleiben kompatibel. Xcode-Projekt, Scheme und Swift-Module behalten technische Namen.
- Das Entwicklungspackaging verarbeitet und erzeugt Saywing.app. Die Markenumstellung lädt keine Modelle und veröffentlicht keine Pakete.

## Vorlesekapsel und Bedienung

Die sichtbare aktive Kapsel ist **136 × 28 pt** groß; die transparente Interaktionsfläche bleibt 136 × 44 pt. In Ruhe zeigt sie Wellenform und Stop; bei Hover wechselt die Wellenform zu Pause/Fortsetzen und Optionen. Keine abgesetzte Schaltfläche und keine Größenänderung bei Hover. Solange das Popover offen ist, bleiben seine Bedienelemente sichtbar. Menü und VoiceOver bieten Zugang ohne Hover; seitliche Popover öffnen sich zum Bildschirm hin. Die neue Saywing-Palette gilt auch für diese kompakte Variante. Vorlesen und Diktieren teilen neun 2,5-pt-Balken mit 3-pt-Abstand, denselben Pegelverlauf und dieselben flachen Wartepunkte. Dekoratives Leuchten, Aufblühen und Überschwingen entfallen. Klänge und sofortiges Stop-Verhalten bleiben erhalten. Siehe [Prüfprotokoll](../integrated-capsule-verification.md).

## Diktierkapsel und Aufnahme

Nach Eigentümerkorrektur am 13.10.2026 ist die Diktieranzeige eine **textfreie Mini-Leiste mit 120 × 28 pt**. Sie ersetzt die zu große 360 × 44-pt-Fassung. Referenz sind die schwebende Flow Bar und ihre Kreuz-/Quadrat-Aktionen aus [Wispr Flows Bedienhinweisen](https://docs.wisprflow.ai/articles/6391241694-use-flow-hands-free). Die Maße sind unsere Implementierungsentscheidung, keine behaupteten Wispr-Messwerte.

Links steht ein kleines Kreuz zum Verwerfen, mittig reagieren neun Pale-Leaf-Balken auf den tatsächlichen Eingangspegel, rechts beendet ein kleines Quadrat die Aufnahme und startet Erkennung/Einfügung. Keine sichtbaren Texte, Daueranzeige oder Mikrofon-Illustration während der Aufnahme. Die primäre Beenden-Taste sitzt wieder in einer kleinen, sanft aufgehellten Kreisfläche; das Verwerfen-Kreuz bleibt zurückhaltend. Die getrennten unsichtbaren Zielflächen sind 32 × 44 pt groß, ohne sich zu überlagern.

Der Forest-Hintergrund, die feine Lichtkante und gedämpfte Schatten verbinden sie mit der Vorlesekapsel. Stille bleibt flach. Während der lokalen Erkennung wandert nur die Helligkeit flacher Punkte. Erfolg, unbestätigtes Einfügen und Fehler erhalten unterschiedliche kleine Symbole; alle Zustände behalten dieselbe Größe. Beschreibungen stehen über VoiceOver, optionale Tooltips und das Diktierfenster zur Verfügung.

Die Kapsel nimmt dem ursprünglichen Textfeld keinen Fokus. Beide Kapseln erscheinen mit einem 140-ms-Einblender und einer dezenten, kritisch gedämpften Skalierung von 96 auf 100 Prozent; bei reduzierter Bewegung bleibt nur der kurze Einblender. Die Pegelanzeige ist über CADisplayLink an die Bildwiederholrate gebunden; ihre Reaktion hängt von der verstrichenen Zeit ab. Reduzierte Bewegung setzt die Pegelanzeige statisch; reduzierte Transparenz oder erhöhter Kontrast macht die Fläche deckend. Verwerfen blendet sofort aus und beendet die Animationsuhr. Keine zusätzlichen Aufnahme-Klänge, kein Audio-/Textinhalt in der Darstellung und keine versteckte Hintergrundaufnahme.

## Tonalität

Ruhig, direkt, konkret. Handlung und Ergebnis erklären. Keine unbelegten Produktivitätszahlen, autonome Aufnahmen, automatisches Senden, universelle Kompatibilität oder erfundene Nutzerstimmen versprechen.

## Noch zu validieren

[Namensrecherche](SAYWING_RESEARCH.md): vorhandener spanischer Firmenname, registrierte .com-Domain, kein .app-RDAP-Eintrag zum Prüfzeitpunkt, null TMview-Treffer für die Basisabfrage. Das ist keine rechtliche Freigabe oder Garantie der Domainverfügbarkeit.

Der Name ist vom Eigentümer ausgewählt. Ein echter Verständlichkeitstest bleibt offen; das [lokale Testblatt](name-test.html) ist vorbereitet, es wurden keine Personen befragt. Domainregistrierung, Markenanmeldung, Veröffentlichung und Outreach wurden nicht ausgeführt. Tatsächliche technische Ergebnisse stehen in [SAYWING_VERIFICATION.md](SAYWING_VERIFICATION.md).

## Gemeinsame Bewegungsregeln

Der [Apple-Design-Review](APPLE_DESIGN_REVIEW.md) dokumentiert die Umsetzung nach dem vom Eigentümer genannten Skill. Die Materialtiefe, 28-pt-Höhe, feine Mint-Kante, Schatten und Wartebewegung sind identisch. Unterschiedliche Breiten entstehen durch die jeweiligen Aktionen. Vorlesen behält Pause, Warteschlange und Docking; Diktieren bleibt 120 × 28 pt ohne Text oder Timer. Die Bereichs-Auswahlreise erklärt nur den Vorlesepfad und bleibt eine eigene kontextbezogene Rückmeldung. Abbruch reagiert weiterhin sofort.

### Feinschliff nach Eigentümerfeedback

Der Wunsch nach mehr Nähe zur vorherigen Gestaltung bringt etwas Materialtiefe zurück: weichere mintfarbene Lichtkante, sattes Wacholdergrün im Verlauf, etwas breitere und rundere Balken mit helleren Spitzen und dezenter pegelabhängiger Lichtstreuung. Die runde primäre Taste greift die frühere Vorleseform auf. Beide Aktivitäten teilen diese Behandlung; die 28-pt-Höhe, kleinen Diktiermaße und gemeinsame ruhige Bewegung bleiben bestehen. Keine zusätzlichen Lichtspuren, Abschlussringe oder Dauertexte.

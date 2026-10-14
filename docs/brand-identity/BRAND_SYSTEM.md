# Saywing — verbindliche Markenidentität

Am **14.10.2026** hat der Eigentümer Richtung **B — Text wird Stimme** mit der Farbpalette der B-Vorlage (Tintenblau, warmes Weiß, Petrol und Apricot) zur Umsetzung freigegeben. Name, Funktionszusatz und Leitgedanke bleiben erhalten. Dieses Dokument ersetzt die [Quiet-Owl-Identität vom 13.10.2026](BRAND_SYSTEM_2026-10-13.md); die [frühere Entwicklung](BRAND_SYSTEM_2026-09.md) bleibt als Historie erhalten.

## Name und Sprache

| | Deutsch | English |
|---|---|---|
| Name | Saywing | Saywing |
| Zusatz | Vorlesen & Diktieren für macOS. | Read aloud & dictate on your Mac. |
| Leitgedanke | Text hören. Mit der Stimme schreiben. | Hear text. Write with your voice. |
| Aktion 1 | Vorlesen — Bildschirmbereich wählen. Zuhören. | Read aloud — Select a screen region. Listen. |
| Aktion 2 | Diktieren — Sprechen. Text einfügen. | Dictate — Speak. Insert text. |

Eine native Menüleisten-App, eine Marke, zwei ausdrücklich gewählte Aktionen. Das Zeichen verbindet horizontale Textzeilen mit vertikalen Sprachbalken; der Zusatz benennt beide Funktionen ausdrücklich. Schreibweise immer **Saywing**, nicht SayWing oder Saywring.

**Aktueller Funktionsstand:** lokales Vorlesen und ausdrücklich gestartetes lokales Diktieren sind im privaten Entwicklungsbuild integriert. Keine universelle Textfeld-Kompatibilität oder öffentliche Release-Reife versprechen. Modellwahl, Berechtigungen und die noch offenen Prüfungen stehen im [Diktier-Prüfprotokoll](../dictation-integration-verification.md).

Datenschutz bleibt eine Produkteigenschaft: kein Cloud-OCR/TTS/ASR, kein Konto, keine Standardtelemetrie und keine dauerhafte Inhaltshistorie. Der Vorlesepfad schreibt nicht automatisch in die Zwischenablage. Beim expliziten Diktieren wird sie zum Einfügen kurz verwendet und nur bei unveränderter Eigentümerschaft wiederhergestellt; neuere Kopien haben Vorrang. Keine Mikrofonaufnahme beim App-Start.

## Bildmarke und Assets

- [Flache Bildmarke](assets/saywing-logo.png): Text wird Stimme in einheitlichem Tintenblau auf transparentem Grund.
- [App-Icon](assets/saywing-app-icon.png): warmweißes Text-/Stimmzeichen auf tintenblauer Icon-Fläche; der rechte Sprachbalken ist Petrol.
- [Menüleistenzeichen](assets/saywing-menubar.png): einfarbige Alpha-Vorlage desselben Text-/Stimmzeichens.
- [Visuelle Vorschau](saywing.html) und [maschinenlesbare Tokens](assets/brand-tokens.json).

Zwei kurze horizontale Textlinien stehen über einer längeren unteren Linie, die rechts weich in einen kurzen Sprachbalken aufbiegt. Daneben stehen ein hoher und ein mittelhoher vertikaler Balken. Gleichmäßige Strichgewichte, runde Enden und offene Zwischenräume prägen die Form. Keine Eule, kein zusätzliches Mikrofon und kein Schmucksymbol. Die Bildmarke darf einfarbig verwendet werden; im App-Icon betont ausschließlich der rechte Balken mit Petrol den Sprachrhythmus. Lautsprecher und Mikrofon erklären die einzelnen Aktionen weiterhin separat mit Text.

Die ausgewählte Richtung ist als transparente Rastermaster umgesetzt. Native Asset-Katalog-Exporte sind implementiert. Mathematisch exakte Vektoren und ein Icon-Composer-Layerstapel bleiben eine Produktionsverbesserung; diese Dateien sind keine Vektormaster.

## Farbe und Schrift

| Token | Wert | Anwendung |
|---|---|---|
| Ink Navy | `#172B3A` | Logo, Wortmarke und dunkle Markenflächen |
| Paper | `#F4F2EC` | Warmer heller Hintergrund und inverse Schrift |
| Petrol | `#266D79` | Rechter Icon-Balken und Bedienelemente auf hellen Flächen |
| Apricot | `#E4B78F` | Sparsamer dekorativer Akzent; Hinweise auf dunklen Flächen |
| Deep Navy | `#0E1D28` | Dunkle Vorlese- und Diktierkapsel |
| Pale Petrol | `#8BCAD1` | Zugängliche Aktivitätsbalken und Bedienelemente auf dunklen Flächen |
| Paper Light | `#DDEFEF` | Helle Kapselakzente |

Die ersten vier Farben stammen exakt aus der vom Eigentümer bevorzugten Vorlage. Die drei abgeleiteten Oberflächen-/Aktivitätsfarben sichern die Lesbarkeit der nativen Bedienelemente. Generierte Raster-Icons enthalten Materialverläufe; die Farbwerte sind die verbindlichen UI-Tokens.

Berechnete Kontraste: Ink Navy/Paper **13,00:1**, Petrol/Paper **5,29:1**, Pale Petrol/Deep Navy **9,36:1**, Pale Petrol/Ink Navy **7,95:1**. Apricot/Paper erreicht nur **1,64:1**: auf hellen Flächen ausschließlich dekorativ, nicht als Text oder alleinige Kontrollkontur. Apricot/Deep Navy erreicht **9,36:1**. Auf wechselndem Bildschirminhalt garantiert eine einzelne Rahmenfarbe keinen Kontrast; Abdunklung und Auswahlgeometrie bleiben wichtig. Zustände nie ausschließlich durch Farbe vermitteln.

Schrift: native macOS-Systemschrift in der App; lokale System-Sans-Serif in der Vorschau. Keine extern geladenen Fonts. Rundum mindestens eine Balkenbreite Freiraum um die sichtbare Bildmarke. Für kleine Darstellungen die exportierte Menüleistenvorlage verwenden; ihr Alphakanal erhält die einfarbige Form ohne die App-Icon-Fläche. Name und erklärender Zusatz stehen bei Erstkontakt zusammen.

## Native Umsetzung

- Buildprodukt **Saywing.app**, Programmdatei **Saywing**.
- Einstellungen und Einrichtung zeigen Namen, App-Icon, Zusatz und ehrlichen Entwicklungsstand.
- Menüleiste: Template-Zeichen mit vom System gewählter Hell-/Dunkelfarbe. Tooltip und zugänglicher Name enthalten den aktuellen Zustand; im Menü bleibt er sichtbar lesbar.
- Vorlese- und Diktierkapsel: gemeinsame Blau-/Petrolpalette, Oberfläche und Bewegungsregeln; eigenständige Aktionen und zugängliche Beschreibungen. Apricot bleibt Hinweis-/Fehlerfarbe.
- `sh scripts/export-app-icon.sh` erzeugt App-Icon-Größen und 22-pt-Menüvorlagen in 1×/2×/3× aus den bestätigten Mastern.
- Bundle-ID `com.christopherbobel.OpenScreenReader`, Einstellungsschlüssel und `Application Support/OpenScreenReader` bleiben kompatibel. Xcode-Projekt, Scheme und Swift-Module behalten technische Namen.
- Das Entwicklungspackaging verarbeitet und erzeugt Saywing.app. Die Markenumstellung lädt keine Modelle und veröffentlicht keine Pakete.

## Vorlesekapsel und Bedienung

Die sichtbare aktive Kapsel ist **136 × 28 pt** groß; die transparente Interaktionsfläche bleibt 136 × 44 pt. In Ruhe zeigt sie Wellenform und Stop; bei Hover wechselt die Wellenform zu Pause/Fortsetzen und Optionen. Keine abgesetzte Schaltfläche und keine Größenänderung bei Hover. Solange das Popover offen ist, bleiben seine Bedienelemente sichtbar. Menü und VoiceOver bieten Zugang ohne Hover; seitliche Popover öffnen sich zum Bildschirm hin. Die gemeinsame Saywing-Palette gilt auch für diese kompakte Variante. Vorlesen und Diktieren teilen neun 2,5-pt-Balken mit 3-pt-Abstand, denselben Pegelverlauf und dieselben flachen Wartepunkte. Dekoratives Leuchten, Aufblühen und Überschwingen entfallen. Klänge und sofortiges Stop-Verhalten bleiben erhalten. Siehe [Prüfprotokoll](../integrated-capsule-verification.md).

## Diktierkapsel und Aufnahme

Nach Eigentümerkorrektur am 13.10.2026 ist die Diktieranzeige eine **textfreie Mini-Leiste mit 120 × 28 pt**. Sie ersetzt die zu große 360 × 44-pt-Fassung. Referenz sind die schwebende Flow Bar und ihre Kreuz-/Quadrat-Aktionen aus [Wispr Flows Bedienhinweisen](https://docs.wisprflow.ai/articles/6391241694-use-flow-hands-free). Die Maße sind unsere Implementierungsentscheidung, keine behaupteten Wispr-Messwerte.

Links steht ein kleines Kreuz zum Verwerfen, mittig reagieren neun helle Petrol-Balken auf den tatsächlichen Eingangspegel, rechts beendet ein kleines Quadrat die Aufnahme und startet Erkennung/Einfügung. Keine sichtbaren Texte, Daueranzeige oder Mikrofon-Illustration während der Aufnahme. Die primäre Beenden-Taste sitzt wieder in einer kleinen, sanft aufgehellten Kreisfläche; das Verwerfen-Kreuz bleibt zurückhaltend. Die getrennten unsichtbaren Zielflächen sind 32 × 44 pt groß, ohne sich zu überlagern.

Der Deep-Navy-Hintergrund, die feine Lichtkante und gedämpfte Schatten verbinden sie mit der Vorlesekapsel. Stille bleibt flach. Während der lokalen Erkennung wandert nur die Helligkeit flacher Punkte. Erfolg, unbestätigtes Einfügen und Fehler erhalten unterschiedliche kleine Symbole; alle Zustände behalten dieselbe Größe. Beschreibungen stehen über VoiceOver, optionale Tooltips und das Diktierfenster zur Verfügung.

Die Kapsel nimmt dem ursprünglichen Textfeld keinen Fokus. Beide Kapseln erscheinen mit einem 140-ms-Einblender und einer dezenten, kritisch gedämpften Skalierung von 96 auf 100 Prozent; bei reduzierter Bewegung bleibt nur der kurze Einblender. Die Pegelanzeige ist über CADisplayLink an die Bildwiederholrate gebunden; ihre Reaktion hängt von der verstrichenen Zeit ab. Reduzierte Bewegung setzt die Pegelanzeige statisch; reduzierte Transparenz oder erhöhter Kontrast macht die Fläche deckend. Verwerfen blendet sofort aus und beendet die Animationsuhr. Kein Audio-/Textinhalt in der Darstellung und keine versteckte Hintergrundaufnahme.

Seit 2026-10-14 (Eigentümerentscheidung) hat das Diktieren drei eigene, kurze Klänge aus der Holz-und-Wasser-Familie: Mikrofon an (C4), freihändig eingerastet (G4, eine Quinte darüber) und Mikrofon aus (G3, gedämpft, ohne Wasser). Häufige Klänge bleiben kurz, warm und schlicht; Wasser und Raum bleiben dem Abschluss vorbehalten. Verwerfen bleibt stumm. Freihändiges Aufnehmen zeigt sich nur an der Beenden-Taste: Sie füllt sich hell petrolfarben und rastet einmal kritisch gedämpft ein. Kein Text, kein Timer, kein Leuchtring.

## Tonalität

Ruhig, direkt, konkret. Handlung und Ergebnis erklären. Keine unbelegten Produktivitätszahlen, autonome Aufnahmen, automatisches Senden, universelle Kompatibilität oder erfundene Nutzerstimmen versprechen.

## Noch zu validieren

[Namensrecherche](SAYWING_RESEARCH.md): vorhandener spanischer Firmenname, registrierte .com-Domain, kein .app-RDAP-Eintrag zum Prüfzeitpunkt, null TMview-Treffer für die Basisabfrage. Das ist keine rechtliche Freigabe oder Garantie der Domainverfügbarkeit.

Der Name ist vom Eigentümer ausgewählt. Ein echter Verständlichkeitstest bleibt offen; das [lokale Testblatt](name-test.html) ist vorbereitet, es wurden keine Personen befragt. Domainregistrierung, Markenanmeldung, Veröffentlichung und Outreach wurden nicht ausgeführt. Die aktuelle Markenumstellung ist in [TEXT_TO_VOICE_VERIFICATION.md](TEXT_TO_VOICE_VERIFICATION.md) dokumentiert; ältere Ergebnisse stehen in [SAYWING_VERIFICATION.md](SAYWING_VERIFICATION.md).

## Gemeinsame Bewegungsregeln

Der [Apple-Design-Review](APPLE_DESIGN_REVIEW.md) dokumentiert die Umsetzung nach dem vom Eigentümer genannten Skill. Die Materialtiefe, 28-pt-Höhe, feine Petrol-Kante, Schatten und Wartebewegung sind identisch. Unterschiedliche Breiten entstehen durch die jeweiligen Aktionen. Vorlesen behält Pause, Warteschlange und Docking; Diktieren bleibt 120 × 28 pt ohne Text oder Timer. Die Bereichs-Auswahlreise erklärt nur den Vorlesepfad und bleibt eine eigene kontextbezogene Rückmeldung. Abbruch reagiert weiterhin sofort.

### Feinschliff nach Eigentümerfeedback

Der Wunsch nach mehr Nähe zur vorherigen Gestaltung bringt etwas Materialtiefe zurück: weichere helle petrolfarbene Lichtkante, sattes Tintenblau im Verlauf, etwas breitere und rundere Balken mit helleren Spitzen und dezenter pegelabhängiger Lichtstreuung. Die runde primäre Taste greift die frühere Vorleseform auf. Beide Aktivitäten teilen diese Behandlung; die 28-pt-Höhe, kleinen Diktiermaße und gemeinsame ruhige Bewegung bleiben bestehen. Keine zusätzlichen Lichtspuren, Abschlussringe oder Dauertexte.

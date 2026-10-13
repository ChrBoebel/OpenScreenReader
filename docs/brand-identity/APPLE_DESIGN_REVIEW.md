# Saywing: gemeinsame Oberflächen und Bewegung

Review vom 13.10.2026. Grundlage ist der vom Eigentümer verlinkte [Apple-Design-Skill von Emil Kowalski](https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md). Seine Prinzipien wurden auf AppKit übertragen; kein fremder Implementierungscode wurde übernommen.

## Befund und Umsetzung

Die Vorleseanzeige hatte eine 44-pt-Fläche, leuchtende Balken, eine wandernde Lichtspur, Atembewegung, Abschlussring und eine überschwingende Öffnung. Diktieren verwendete eine flache 28-pt-Leiste mit einem einfacheren Pegelmesser. Gemeinsame Farben allein konnten diese Unterschiede nicht ausgleichen.

Beide Aktivitäten verwenden jetzt dieselbe 28-pt-Oberfläche, Forest-Material, Mint-Kante, Schatten, Balkengeometrie und zeitabhängige Pegelreaktion. Auf Stille sinken die Balken tatsächlich ab. Vorbereitung und Erkennung zeigen denselben ruhigen Helligkeitslauf. Beide erscheinen mit kurzer Einblendung und kritisch gedämpfter Skalierung. Das Vorlesen verliert die dekorativen Leucht- und Aufblüheffekte; die Aufnahme bleibt klein und textfrei. CADisplayLink ersetzt den 30-Hz-Timer des Diktierwidgets. Reduzierte Bewegung, reduzierte Transparenz und erhöhter Kontrast werden berücksichtigt.

Die sichtbare Vorlesekapsel misst 136 × 28 pt, ihre Interaktionsfläche weiterhin 136 × 44 pt. Diktieren bleibt bei 120 × 28 pt mit getrennten 32 × 44-pt-Klickflächen. Die zusätzliche Breite beim Vorlesen trägt Pause und Optionen bei Hover. Docking, Warteschlange, Fokus im ursprünglichen Textfeld und sofortiger Abbruch bleiben erhalten. Die Auswahlreise erklärt weiterhin den räumlichen Zusammenhang zwischen Bildschirmbereich und Vorlesen; sie gehört nicht zur Mikrofonaufnahme.

## Weitere konkrete Verbesserungen

1. **Eine Sprache pro Oberfläche.** Menü und Einstellungen mischen weiterhin englische Vorleseaktionen mit deutschen Diktieraktionen. Beispiel: „Playback Controls…“ neben „Diktieren einrichten & testen…“. Nächster Schritt: gemeinsamer lokalisierter Satz für Aktionen, Status und Hilfen; Standard in der Systemsprache.
2. **Ein gemeinsamer Einrichtungsablauf.** Die Einstellungen verwenden native gruppierte Bereiche; das Diktierfenster wirkt mit Modellwahl, Clipboard-Verzögerung, Berechtigungszeile, zwei Textfeldern und Demo-Tasten gleichzeitig wie ein Diagnosetool. Vorgeschlagene Reihenfolge: Berechtigungen → kurzes Testdiktat → bereit. Modell und Einfügeverzögerung in „Erweitert“, Diagnosedemos separat. Dies ist ein Vorschlag, noch kein umgesetzter Umbau.
3. **Gemeinsame Positionierung.** Vorlesen kann an drei Kanten angedockt werden; Diktieren erscheint stets unten mittig. Perspektivisch beide Aktivitäten an derselben vom Nutzer gewählten Stelle zeigen, ohne die Auswahl des Lesebildschirms oder das ursprüngliche Diktier-Zielfeld zu verlieren. Noch nicht umgesetzt.

## Verifikation und Grenzen

- Neue Tests zunächst rot: fehlende gemeinsame Oberflächen-/Meter-API.
- Anschließend alle 128 Swift-Tests in 9 Suites erfolgreich; zusätzlich zwei berechtigungsabhängige XCTest-Prüfungen übersprungen (Bildschirmaufnahme und globales Escape im Testhost).
- Geprüft: übereinstimmende Pegelgeometrie, Ausklingen in Stille, identische zeitliche Reaktion bei 60/120 Hz, Freigabe der Display-Link-Views, reduzierte Bewegung, Klickflächen, Docking, Drag-/Klicktrennung, Pause, Warteschlange und veraltete Abbruchereignisse.
- Native AppKit-Renderings für Vorlesen an allen drei Kanten und sämtliche Diktierzustände; gemeinsames Vergleichsbild mit synthetischen Pegeln. Kein Screenshot privater Bildschirminhalte und kein Mikrofonmitschnitt für diese Renderings.
- Release-Build erfolgreich. Die bestehende lokale Laufzeit wird beim Update übernommen; keine Modelldownloads oder Veröffentlichung.
- Reale Fn-Mikrofonaufnahme und systemweite Bedienungshilfen wurden durch diese Ansichtstests nicht ersetzt. Die bereits zuvor schwankende Clipboard-Wiederherstellung im integrierten Demo-Selbsttest bleibt separat offen; diese Änderung betrifft deren Implementierung nicht.

Abschließende Prüfung: Nach der Korrektur des erneuten Einblendens weitere 32 Tests in den beiden betroffenen Suites erfolgreich. Native Vergleichsexporte anschließend mit 11 Diktieransichtstests erfolgreich. Signierter Build in `/Applications/Saywing.app` installiert; alle 18 Swift-Quelldateien stimmen mit dem eingebetteten Build-Inventar überein. Die bisherige Version bleibt unter `.build/saywing-brand/previous-mini-capsule/Saywing.app` erhalten. Start und Einstellungen wurden in der nativen UI geprüft; ein erneutes Live-Diktat war nicht Teil dieser Prüfung.

## Feinschliff nach Rückmeldung zum vorherigen Design

Mehr Nähe zur früheren Farb- und Formensprache: tieferer Wacholder-Verlauf mit sanfter oberer Lichtkante, 2,5-pt-Balken mit helleren Mint-Spitzen und dezenter pegelabhängiger Lichtstreuung, kreisförmig hinterlegte primäre Stop-Taste. Beide Kapseln behalten dieselbe gemeinsame Bewegung und ihre kleinen Maße. Die vorhandenen 32 Tests der beiden Ansichten und der Release-Build bestehen; native Vergleichsansichten erneut gerendert und visuell geprüft. Keine Änderung am Aufnahme-, Einfüge- oder Abbruchablauf.

## Zweites Review und Umsetzung — 14.10.2026

Ein zweites Review nach demselben Skill fand 16 weitere Punkte: Sprache, Lesbarkeit, Einrichtung, Einstellungen, Kurzbefehlsfeld, Menü, Auswahl-Overlay (⌘⇧4-Modifikatoren, Einblendung, Hinweis, Klick liest Absatz), Andock-Physik (Wurf-Projektion, Federn mit Geschwindigkeitsübergabe, Gummiband, Haptik beim Einrasten), Flugkurve und Klänge der Stop-Taste. Der Eigentümer hat alle Punkte freigegeben. Die drei offenen Punkte oben (eine Sprache, ein Einrichtungsablauf, Einstellungen statt Diagnosefenster) sind damit umgesetzt; die gemeinsame Positionierung beider Kapseln bleibt offen. Umsetzung, Tests und Grenzen: [Apple-Design-Verfeinerung](../apple-design-refinements-verification.md).

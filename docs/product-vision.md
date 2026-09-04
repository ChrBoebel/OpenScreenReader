# Product vision

## Vision

OpenScreenReader soll sich wie eine kleine native macOS-Systemfunktion anfühlen: Hotkey drücken, sichtbaren Text markieren und ihn ohne weiteren Dialog mit einer natürlichen Stimme hören.

## Positionierung

> **Markieren. Zuhören. Komplett lokal und Open Source.**

Englisch:

> **Select. Listen. Stay private.**

Das Projekt ist weder ein vollständiger Screenreader noch eine Dokumentbibliothek oder Cloud-TTS-Plattform. Es konzentriert sich auf einen einzigen schnellen Ablauf für beliebigen sichtbaren Bildschirmtext.

## Kernversprechen

1. **Open Source:** Datenflüsse, Netzwerkzugriffe und Modellintegration sind öffentlich überprüfbar.
2. **Local by design:** Der offizielle MVP enthält das lokale Standardmodell; OCR und TTS erfolgen nach der Installation vollständig auf dem Mac.
3. **Volle Kontrolle:** kein Konto, keine Cloud-Synchronisation, keine Telemetrie im offiziellen Build und keine standardmäßige Historie.
4. **Natürliche Stimme:** moderne lokale neuronale TTS statt alleiniger Verwendung von macOS-Systemstimmen.
5. **Minimale Reibung:** eine Geste vom sichtbaren Text bis zur Wiedergabe.

## Zielgruppen

- Menschen mit Lesebelastung, Dyslexie oder ADHS, die keinen vollständigen Screenreader benötigen;
- Knowledge Worker, die kurze Passagen aus PDFs, Präsentationen, Tickets, Chats oder Videos hören möchten;
- datenschutzbewusste Nutzer in Forschung, Medizin, Recht oder Unternehmen;
- deutsch- und englischsprachige Nutzer, später auch Sprachlernende.

## Bewusste Abgrenzung

OpenScreenReader soll nicht als Ersatz für VoiceOver vermarktet werden. Semantische Navigation, Bedienelementerkennung und vollständig blinde Systembedienung bleiben außerhalb des ersten Produktumfangs.

## MVP-Erfolgskriterien

Der MVP ist nur überzeugend, wenn er:

1. hörbar natürlicher als Apple-System-TTS klingt;
2. bei warmem Modell subjektiv sofort zu sprechen beginnt;
3. mindestens so einfach wie etablierte Bildschirm-OCR-Tools bedienbar ist;
4. nach der Installation ohne Netzwerk und ohne separate Modelleinrichtung funktioniert;
5. den laufenden Vorgang jederzeit zuverlässig abbrechen kann.

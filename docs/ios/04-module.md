# 04 · Module im Detail

Alle Inhalte der Web-App bleiben erhalten. Hier steht pro Bereich, was die iOS-App zusätzlich tut.

## Heute

- Tagesaufgaben wie in der Web-App, ergänzt um **automatische Erledigung**: Ein Check-in von der Watch,
  eine Atemübung mit Haptik oder eine über Siri gestartete Sitzung zählen ohne weiteres Zutun.
- **Health-Kacheln**: Schlaf letzte Nacht, HRV-Trend, Lärmbelastung gestern, Kopfhörer-Dosis heute.
- **Lautheits-Trend** wie bisher, zusätzlich mit Tageszeit-Streifen.
- Erinnerungen konfigurierbar: Check-in-Zeitfenster, Sitzungen, Lektion.

## Labor

| Schritt | iOS-Ergänzung |
| --- | --- |
| Kopfhörer-Check | Erkennt angeschlossenes Gerät, lädt Kalibrierprofil, warnt bei Lautsprecher-Wiedergabe; AirPods: Hinweis, adaptive Funktionen für Messungen zu deaktivieren |
| Tinnitus-Spektrum | Unverändert; Pegel in kalibrierten dB bei bekanntem Gerät |
| Feinabstimmung | Frequenz-Pad als `Canvas` mit Drag-Geste; Haptik bei Oktavgrenzen |
| Hörprofil | **Import aus Apples Hörtest** (HealthKit-Audiogramm, 250 Hz–8 kHz); eigener Test nur 10–16 kHz; Zusammenführung zu einer Kurve. Hinweis auf Hörgerätefunktion der AirPods Pro bei Abfall |
| Somatik-Check | Zusätzlich **Nacken-Beweglichkeit** per Kopftracking messen (Rotation, Seitneigung, Flexion in Grad) als Basiswert fürs Körper-Modul |
| RI-Labor | Verblindung wie bisher; Bewertung mit Haptik-Signal zum Start; Live-Kurve; Pausen-Timer zwischen Durchgängen mit Benachrichtigung |

## Klang

- Vier Modi wie bisher: Klanganreicherung (inkl. AM 10 Hz), Reset-Sitzung, Notched Sound, CR.
- **Hintergrundwiedergabe**, Sperrbildschirm-Steuerung, Sleep-Timer mit 60-s-Fade, Live Activity.
- **Eigene Musik** aus Mediathek (nur DRM-freie Titel) und Dateien-App durch den Notch.
- **Automationen** über Kurzbefehle: beim Schlafen-Fokus Klanganreicherung starten.
- **Pegel in dB SPL (geschätzt)** bei kalibriertem Gerät; harter Deckel (siehe 05 und 08).
- Vorher/Nachher-Bewertung bleibt; bei Sitzungen aus dem Schlaf-Fokus entfällt sie.

## Kopf

- 8 Lektionen und alle Übungen aus der Web-App.
- Atemübung mit **Haptik** (iPhone oder Watch) und optional geschlossenen Augen.
- Geführte Übungen als Audio (TTS mit `AVSpeechSynthesizer` in ruhiger Stimme oder eingesprochen),
  damit niemand aufs Display schauen muss.
- Gedanken-Check und Notfallplan wie bisher; Notfallplan zusätzlich als Widget erreichbar.
- Achtsamkeits-Minuten nach HealthKit schreiben.

## Körper (neu)

Siehe 06. Dehn- und Entspannungsprogramm für Nacken, Schultern und Kiefer mit animierter Anleitung
und optionalem Kopftracking. Für alle Nutzer als Entspannung, für Nutzer mit positivem Somatik-Check
als gezielter Baustein.

## Verlauf

- Alles aus der Web-App: Lautheit/Belastung, MML-Verlauf, „Was wirkt bei dir?“ mit Konfidenzbereich,
  Tageszeit, Auslöser, Tagesrückblick, Wochen-Check.
- **Automatische Auslöser** aus HealthKit: Lärmtage, kurze Nächte, niedrige HRV. Handeingaben nur noch
  für Koffein/Alkohol/Notizen.
- **Körper-Verlauf**: Nackenbeweglichkeit über Wochen, Kieferanspannung (Selbsteinschätzung).
- Export als JSON (kompatibel mit Web-App) und als PDF-Bericht für den HNO-Termin (Audiogramm, Spektrum,
  MML, Verlauf der letzten 8 Wochen).

## Wissen

- Inhalte aus `learn.ts`, datiert, mit Quellenliste.
- Zusätzlich: „Nächste Schritte in Deutschland“ mit Deep-Links (Hörtest in Einstellungen, DiGA-Verzeichnis).

## Watch-App

- Check-in (zwei Skalen, Digital Crown oder Tipp).
- Atemübung mit Haptik, 1/3/5 Minuten.
- Komplikation mit Tagesfortschritt; Sitzung von der Watch starten/stoppen.

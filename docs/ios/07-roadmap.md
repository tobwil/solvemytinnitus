# 07 · Roadmap

> **Stand der Umsetzung (Oktober 2026):** Phasen 0–2 und der Großteil von Phase 3 sind in [`ios/`](../../ios/README.md)
> umgesetzt. Offen sind Rive-Assets (optional), englische Lokalisierung, ein vollständiges VoiceOver-Audit und
> echte Kalibriermessungen der Kopfhörerprofile (die Werte im Code sind konservative Platzhalter).

Zeitangaben sind Schätzungen für eine Person mit Erfahrung in SwiftUI, in Teilzeit.

## Phase 0 · Fundament (1–2 Wochen)

- Xcode-Workspace, Packages `TinnitusCore` und `TinnitusAudio`, Swift 6, Strict Concurrency.
- Datenmodell in SwiftData, Import des JSON-Exports der Web-App (Migration testen).
- Design-System: Farben, Typografie, Komponenten (Card, Chip, Evidence, Range, Scale10, Ring).
- Audio-Graph mit Ton, Rauschen, Notch; Offline-Test der Filterantwort.

**Done:** Web-Export importierbar, ein Ton und notched Rauschen spielen im Hintergrund.

## Phase 1 · Kern (3–4 Wochen)

- Onboarding mit Kopfhörer-Erkennung und Lautstärke-Anker.
- Labor: Spektrum, Feinabstimmung (Pad), Lautheit, MML, Hörprofil (eigener Test 10–16 kHz + HealthKit-
  Audiogramm-Import), Somatik-Check (ohne Tracking), RI-Labor verblindet.
- Klang: alle vier Modi, Sperrbildschirm-Steuerung, Sleep-Timer, Live Activity.
- Kopf: Lektionen, geführte Übungen mit Haptik, Gedanken-Check, Notfallplan.
- Verlauf: Charts, „Was wirkt bei dir?“, Tageszeit, Auslöser, Tagesrückblick, Wochen-Check.
- Erinnerungen für Check-ins (zufällige Zeiten in Fenstern).

**Done:** Kompletter 8-Wochen-Durchlauf ohne Web-App möglich; TestFlight an 3–5 Betroffene.

## Phase 2 · Nativ ausreizen (3 Wochen)

- HealthKit: Schlaf, HRV, Umgebungslärm, Kopfhörer-Dosis → automatische Auslöser und Health-Kacheln.
- Achtsamkeits-Minuten schreiben.
- Watch-App: Check-in, Atemübung, Komplikation.
- Widgets und App Intents (Siri, Kurzbefehle, Schlaf-Fokus-Automation).
- Körper-Modul mit SwiftUI-Figur (Programme A und B), Kontraindikations-Abfrage.
- Kalibrierprofile AirPods Pro 2/3 inkl. Plausibilisierung über Kopfhörer-Dosis.

**Done:** Ein Tag ohne manuelle Eingabe außer Check-ins liefert vollständige Verlaufsdaten.

## Phase 3 · Feinschliff und Innovation (2–3 Wochen)

- Kopftracking: Beweglichkeitsmessung, geführte Dehnung mit Zielring, Haltungs-Hinweis.
- Rive-Assets für die Figur (optional).
- PDF-Bericht für den HNO-Termin.
- Barrierefreiheit vollständig (VoiceOver-Audit, Dynamic Type XXL, Reduce Motion).
- Lokalisierung Englisch.

**Done:** App-Store-Einreichung vorbereitet (siehe 08).

## Später / Ideen mit Vorbehalt

- iPad-Layout, Mac Catalyst.
- Gemeinsame Auswertung mit HNO/Therapeut per Export-Link (nur auf Wunsch).
- Dekorrelierender Klang (Yukhnovich/Sedley 2025), sobald repliziert: als experimenteller Modus mit Kennzeichnung.
- Teilnahme an Forschung: anonymisierter Export für Studien, Opt-in.

## Nicht geplant

- Eigener Server, Konten, Werbung, Tracking.
- Vibrations-„Bimodal“-Modus (keine Evidenz, siehe Web-Redesign).
- Heilversprechen in Marketing oder App-Store-Text.

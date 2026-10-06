# Tinnitus Lab für iOS

Native Umsetzung des Konzepts in [`docs/ios/`](../docs/ios/README.md). SwiftUI, Swift 6 (Strict Concurrency),
iOS 18.1+, watchOS 11+, SwiftData, Swift Charts, keine Drittbibliotheken.


## UX-Konzept: ein Fluss statt Kacheln

Drei Räume statt fünf Feature-Tabs, eine Farbgeschichte statt einer Farbe pro Bereich:

- **Fluss** – der Tag als eine Geschichte: ein Satz, der den Tag deutet („Leiser als sonst.“), die Tageswelle (Lautheit amber, Geübtes als Teal-Balken, gestern gestrichelt, „jetzt“-Marker), der Check-in direkt im Fluss und eine Zeitleiste von heute Morgen über *Jetzt* (ein nächster Schritt) bis zu dem, was offen ist.
- **Üben** – startet beim Befinden („Er ist laut“, „Einschlafen“, „Verspannt“, „Gedankenkarussell“, „Mein Plan“): ein klarer Vorschlag, dazu passende Übungen, darunter die Bibliothek Klang · Kopf · Körper.
- **Ich** – das Porträt des Tinnitus (Frequenz, Klang, Vorhören), vier Wochen Verlauf, „Was sich zeigt“ in Sätzen, Health, Messungen, Verlauf/Wissen/Einstellungen.
- **Farben:** Teal = Ruhe und alles, was du tust; Amber = der Tinnitus selbst; Schiefer = Belastung. Der Hintergrund wärmt sich nach einem lauten Check-in sichtbar auf und kühlt in 6 Stunden wieder ab (`Ambient`).

## Bauen

```bash
brew install xcodegen      # einmalig
cd ios
xcodegen                   # erzeugt TinnitusLab.xcodeproj aus project.yml
open TinnitusLab.xcodeproj
```

Tests (Pakete, App-Unit-Tests, UI-Smoke-Tests):

```bash
xcodebuild -project TinnitusLab.xcodeproj -scheme TinnitusLab -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

Nur die Logik, ohne Simulator: `cd Packages/TinnitusCore && swift test` bzw. `cd Packages/TinnitusAudio && swift test`.

### Debug-Startargumente

| Argument | Wirkung |
| --- | --- |
| `-uitest` | In-Memory-Store, nichts wird gespeichert |
| `-onboarded` | (mit `-uitest`) Onboarding überspringen |
| `-demo` | (Debug) realistische 25-Tage-Demodaten: Messungen, Check-ins, Sitzungen, Health, Körper |
| `-route tinnituslab://…` | direkt zu einem Screen, z. B. `tinnituslab://progress/overview` oder `tinnituslab://sound/notched?minutes=30` |

Im Simulator gilt die Audioausgabe als Kabel-Kopfhörer, damit die Messabläufe testbar sind (nur `targetEnvironment(simulator)`).

## Aufbau

```
ios/
├── project.yml                  XcodeGen-Definition aller Targets
├── Packages/
│   ├── TinnitusCore/            Logik ohne UI (iOS, watchOS, macOS-Tests)
│   │   ├── Models/              SwiftData-Modelle (CloudKit-kompatibel), Werttypen
│   │   ├── Program/             8-Wochen-Programm, Tagesaufgaben, Labor-Schritte, Deep Links
│   │   ├── Analysis/            RI-Ranking, Spektrum, Hörschwellen-Staircase, Konfidenzbereiche,
│   │   │                        Auslöser (inkl. HealthKit), Tageszeit, Dosis, Pegel-Plausibilisierung
│   │   ├── Content/             Lektionen, Übungen, Evidenz, Klangmodi, Körperprogramme
│   │   ├── Signal/              Biquads, 8.-Ordnung-Butterworth-Notch, Rauschen, CR-Sequenzer, Synth
│   │   └── Export/              JSON-Import/-Export kompatibel mit der Web-App (v1-Migration)
│   └── TinnitusAudio/           AVAudioEngine-Graph, Geräteerkennung, Kalibrierprofile,
│                                Hörschutz-Deckel, Dosiszähler, Live-Spektrum, Now Playing, Musik
├── TinnitusLab/                 iOS-App (SwiftUI)
│   ├── App/                     Einstieg, Router, Datenaktionen, Demo-Daten
│   ├── DesignSystem/            Farben, Typografie, Komponenten, Charts, Haptik
│   ├── Services/                Sitzungen (Hintergrund, Live Activity), HealthKit, Erinnerungen,
│   │                            Kopftracking, Sprachausgabe, Watch-Bridge, PDF-Bericht
│   ├── Features/                Onboarding, Fluss (Heute), Üben, Ich, Labor, Klang, Kopf, Körper, Verlauf, Wissen, Einstellungen
│   └── Intents/                 Siri/Kurzbefehle, Fokus-Filter
├── Shared/                      App + Widgets: App-Group-Snapshot, Check-in-Intent, Live-Activity-Attribute
├── TinnitusLabWidgets/          Widgets (Home/Sperrbildschirm), Notfallplan, Live Activity + Dynamic Island
├── TinnitusLabWatch/            watchOS: Check-in (Digital Crown), Atemübung mit Haptik, Klang-Fernbedienung
└── TinnitusLabWatchWidgets/     Komplikation
```

## Umsetzungsstand gegenüber der Roadmap

| Phase | Inhalt | Stand |
| --- | --- | --- |
| 0 | Packages, SwiftData-Modell, Web-JSON-Import, Design-System, Audio-Graph mit Offline-Tests | ✅ |
| 1 | Onboarding mit Geräteerkennung, komplettes Labor, alle vier Klangmodi mit Hintergrund/Sperrbildschirm/Sleep-Timer/Live Activity, Kopf-Training mit Haptik, Verlauf, EMA-Erinnerungen | ✅ |
| 2 | HealthKit (Audiogramm, Schlaf, HRV, Ruhepuls, Atemfrequenz, Lärm, Kopfhörer-Dosis, Achtsamkeitsminuten), automatische Auslöser, Watch-App + Komplikation, Widgets, App Intents inkl. Schlaf-Fokus-Automation, Körper-Modul mit Kontraindikationen, Kalibrierprofile + Plausibilisierung | ✅ (Kalibrierwerte siehe unten) |
| 3 | Kopftracking (Beweglichkeit, geführte Dehnung mit Zielring, Haltungs-Hinweis), PDF-Bericht, Reduce Motion, Fokus-Filter | ✅ |
| 3 | Rive-Assets für die Figur | offen (optional; Schnittstelle `BodyPose` steht) |
| 3 | Lokalisierung Englisch, vollständiges VoiceOver-Audit, Dynamic Type XXL | offen |

## Vor einer Veröffentlichung zu erledigen

- **Kalibrierprofile messen.** Die Werte in `TinnitusAudio/Calibration.swift` sind konservative Platzhalter
  (abgeleitet aus maximalen Ausgangspegeln). Sie müssen pro Terzband am Kunstkopf gemessen werden
  (05-audio-engine, Schritt 2). Bis dahin sind alle dB-SPL-Angaben grobe Schätzungen; die Deckel sind
  bewusst vorsichtig gewählt (unbekannte Geräte werden als laut angenommen).
- **iCloud/CloudKit, App Group und HealthKit** im Developer-Portal für das Team aktivieren
  (`iCloud.io.solvemytinnitus.lab`, `group.io.solvemytinnitus.lab`). Ohne iCloud-Konto oder Container läuft die
  App lokal weiter; iCloud-Sync ist in den Einstellungen abschaltbar.
- **Fachliche Gegenlese** der Inhalte (HNO/Audiologie, Psychotherapie, Physiotherapie), siehe 08.
- **Beta mit Betroffenen** (TestFlight), Fokus: Verständlichkeit, Lautstärke-Gefühl, Nachtnutzung.
- AirPods Pro 2 und 3 melden sich mit gleichem Namen; das Modell wählt man im Kopfhörer-Check.
- Kopftracking-Vorzeichen (Neigung/Drehung) am echten Gerät prüfen; der Simulator liefert keine Bewegungsdaten.

## Tests

| Suite | Inhalt |
| --- | --- |
| `TinnitusCoreTests` (35) | Notch: −3 dB an den Kanten, ≈ −24 dB in der Mitte, 0 dB Passband; Offline-Rendering (Notch, AM, CR-Timing 3 an/2 aus, 150-ms-Töne, Deckel, Fades, Glide); Programmlogik; RI-Auswertung; Staircase; Statistik; Auslöser; Web-JSON v1/v2 inkl. expliziter `null`-Werte; SwiftData-Roundtrip aller Composite-Attribute; Körper-Animation |
| `TinnitusAudioTests` (13) | AVAudioEngine im Offline-Modus: Ohr-Routing, Notch im Graph, −6-dBFS-Deckel, Aufräumen gestoppter Stimmen; Render-Block auf Nicht-Main-Thread; Kalibrierung/Deckel ≤ 85/80 dB SPL; Dosis; Spektrum-Analyser bei 16/44,1/48 kHz |
| `TinnitusLabTests` (5) | Routing, Programmzustand aus dem Store, Widget-Check-in-Import, Sitzungs-Voreinstellungen; Quellen-Links (jede Kurzquelle ergibt einen PubMed- bzw. AWMF-Link) |
| `TinnitusLabUITests` (5) | Onboarding, Inline-Check-in, Check-in per Deep Link, alle drei Räume mit Demodaten, Klangsitzung starten/beenden/bewerten |

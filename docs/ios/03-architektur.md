# 03 · Architektur

## Targets und Packages

```
TinnitusLab.xcworkspace
├── Packages/
│   ├── TinnitusCore/            Swift Package, keine UI, plattformunabhängig (iOS, watchOS, macOS-Tests)
│   │   ├── Models/              SwiftData-Modelle + Codable-DTOs für Export
│   │   ├── Program/             8-Wochen-Programm, Tagesaufgaben, Labor-Schritte
│   │   ├── Analysis/            RI-Ranking, Konfidenzbereiche, Korrelationen, Tageszeit-Muster
│   │   ├── Content/             Lektionen, Übungen, Dehnungen, Evidenztexte (typisiert, lokalisierbar)
│   │   └── Signal/              Reine Signal-Mathematik: Filter-Koeffizienten, Rauschgeneratoren, CR-Sequenzer
│   └── TinnitusAudio/           AVAudioEngine-Graph, Geräteprofile, Kalibrierung, Hörschutz-Limiter
├── TinnitusLab (iOS App)        SwiftUI, Navigation, Screens, HealthKit, Notifications, Intents
├── TinnitusLabWatch (watchOS)   Check-in, Atemübung, Komplikation
├── TinnitusLabWidgets           WidgetKit + Live Activity
└── Tests/                       Swift Testing für Core und Audio (Offline-Rendering)
```

Grundsatz: Alles, was heute in der Web-App unter `src/data/` und `src/audio/` liegt, landet in
`TinnitusCore` bzw. `TinnitusAudio` und ist ohne Simulator testbar.

## Übernahme aus der Web-App

| Web-App | iOS | Anmerkung |
| --- | --- | --- |
| `src/data/model.ts` | `TinnitusCore/Models` | 1:1 als SwiftData-`@Model`-Klassen; zusätzlich `deviceProfile` pro Messung |
| `src/data/program.ts` | `TinnitusCore/Program` | Logik unverändert, Tests dafür schreiben |
| `src/data/mindContent.ts` | `TinnitusCore/Content/Mind` | Lektionen als Markdown-Ressourcen + Struktur in Swift |
| `src/screens/learn.ts` (Evidenz) | `TinnitusCore/Content/Evidence` | Quellen bleiben, Stand datieren |
| `src/screens/progress.ts` (Analysen) | `TinnitusCore/Analysis` | Mittelwert/CI/Pearson als reine Funktionen |
| `src/audio/synth.ts`, `cr.ts` | `TinnitusAudio` | Siehe 05; gleiche Parameter, gleiche Namen |
| `src/ui/*` | SwiftUI-Views | Design-System in `DesignSystem.swift` (Farben, Typografie, Komponenten) |

## Datenmodell (Ergänzungen gegenüber Web)

- `DeviceProfile`: Name, Typ (AirPods Pro 2/3, Kabel, unbekannt), Kalibrier-Offset, Gültigkeit bis 8/16 kHz.
- Jede Messung (`HearingTest`, `TinnitusMatch`, `Spectrum`, `RITrial`) referenziert das `DeviceProfile`.
- `HealthSnapshot` pro Tag: Schlafdauer, HRV, Umgebungslärm-Minuten über 80 dB, Kopfhörer-Dosis.
  Wird aus HealthKit abgeleitet und im Verlauf mit Check-ins verknüpft.
- `BodySession`: Dehnprogramm, Dauer, optional Bewegungsumfang (aus Kopftracking).
- `Session.params` als typisiertes Enum statt `Record<string, …>`.

## Zustand und Navigation

- `@Observable`-ViewModels pro Bereich; keine globale Store-Singleton-Logik, sondern `ModelContext`.
- Tabs: Heute · Labor · Klang · Kopf · Körper, dazu Verlauf und Wissen über die Toolbar (wie Web).
  Alternative mit nur fünf Tabs: Körper unter Kopf einsortieren. Entscheidung bei Phase 2 (siehe 07).
- Deep Links für Widgets/Intents: `tinnituslab://checkin`, `tinnituslab://therapy/enrichment?minutes=30`.

## Mindestanforderungen

- iOS 18.1, watchOS 11, Xcode 16.1+, Swift 6 mit Strict Concurrency.
- Keine Drittbibliotheken im Kern. Für Animationen optional Rive oder Lottie (siehe 06).

## Tests

- `TinnitusCore`: Programm-Logik, RI-Ranking, Konfidenzbereiche, Migration des JSON-Exports der Web-App.
- `TinnitusAudio`: Offline-Rendering des Graphen und Messung der Filterantwort (Notch −24 dB in der Mitte,
  −3 dB an den Oktavgrenzen, wie in der Web-App gemessen), Pegel-Deckel, CR-Timing.
- UI: wenige Smoke-Tests der Hauptflüsse mit XCUITest.

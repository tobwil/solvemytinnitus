# Tinnitus Lab für iOS – Konzept und Plan

Dieser Ordner ist die Arbeitsgrundlage für die native iOS-App. Die Web-App in diesem Repo ist der
funktionierende Prototyp; die iOS-App übernimmt deren Logik und Inhalte und nutzt zusätzlich alles,
was nur nativ geht: Audio im Hintergrund, HealthKit, Apple Watch, AirPods-Sensorik, Erinnerungen,
Widgets und Kurzbefehle.

| Datei | Inhalt |
| --- | --- |
| [01-vision.md](01-vision.md) | Ziel, Leitprinzipien, was die App verspricht und was nicht |
| [02-native-vorteile.md](02-native-vorteile.md) | Welche iOS-Fähigkeiten wir nutzen und wofür genau |
| [03-architektur.md](03-architektur.md) | Targets, Packages, Datenmodell, Übernahme aus der Web-App |
| [04-module.md](04-module.md) | Alle Bereiche der App im Detail: Heute, Labor, Klang, Kopf, Körper, Verlauf, Wissen |
| [05-audio-engine.md](05-audio-engine.md) | AVAudioEngine-Design, Signal-Rezepte, Kalibrierung, Geräteprofile, Hörschutz |
| [06-koerper-dehnung.md](06-koerper-dehnung.md) | Körper-Modul: Nacken- und Kieferübungen, Evidenz, Animationstechnik, AirPods-Kopftracking |
| [07-roadmap.md](07-roadmap.md) | Phasen, Meilensteine, Definition of Done |
| [08-datenschutz-sicherheit-regulatorik.md](08-datenschutz-sicherheit-regulatorik.md) | Datenschutz, Hörschutz, Medizinprodukte-Abgrenzung, App-Store-Anforderungen |

Kurzfassung der Entscheidungen:

- **SwiftUI, Swift 6, iOS 18.1+** (nötig für Audiogramme aus Apples Hörtest in HealthKit), SwiftData, Swift Charts.
- **Ein Swift Package `TinnitusCore`** mit aller Logik und allen Inhalten, ohne UI, plattformunabhängig und testbar.
- **Geräteunabhängig im Kern, AirPods Pro als bevorzugtes Profil** (Kalibrierung, Hörtest-Import, Kopftracking).
- **Fünf Bereiche**: Heute, Labor, Klang, Kopf, Körper (neu, mit animierten Dehnübungen), plus Verlauf und Wissen.
- **Apple Watch** für Check-ins, Atemübungen und Schlaf-/HRV-Daten.
- **Kein Medizinprodukt** in Version 1; Formulierungen und Funktionen bleiben im Wellness-Rahmen (siehe 08).

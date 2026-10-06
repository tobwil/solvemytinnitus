# 02 · Native iOS-Vorteile und wofür wir sie nutzen

Jede Fähigkeit steht hier mit dem konkreten Nutzen für den Tinnitus-Nutzer, nicht als Feature-Liste.
Reihenfolge nach Wichtigkeit.

## 1. Audio im Hintergrund (AVAudioSession `.playback`, Background Mode `audio`)

- Klanganreicherung läuft bei gesperrtem Bildschirm und über Nacht. Das war die größte Schwäche der Web-App.
- Sperrbildschirm und Kontrollzentrum zeigen Titel, Restzeit und Pause/Stopp (`MPNowPlayingInfoCenter`,
  `MPRemoteCommandCenter`).
- Sleep-Timer mit sanftem Ausblenden, Weiterlaufen nach Anruf-Unterbrechung (Interruption-Handling).
- Mischen mit anderen Apps optional (`.mixWithOthers`), z. B. Klanganreicherung unter einem Hörbuch.

## 2. HealthKit

Lesen (mit Einwilligung je Datentyp):

| Datentyp | Nutzen |
| --- | --- |
| Audiogramm (`HKAudiogramSample`) aus Apples Hörtest mit AirPods Pro | Hörprofil bis 8 kHz ohne eigene Messung; eigener Test deckt nur noch 10–16 kHz ab |
| Kopfhörer-Lautstärkebelastung (`headphoneAudioExposure`) | Tägliche Dosis anzeigen, Warnung bei hoher Belastung, Plausibilisierung der eigenen Pegel |
| Umgebungslärm (`environmentalAudioExposure`, Watch) | Automatischer Auslöser „Lärm“ im Verlauf statt Handeingabe |
| Schlafanalyse (`sleepAnalysis`) | Schlafdauer und -qualität automatisch im Tagesrückblick |
| HRV (`heartRateVariabilitySDNN`), Ruhepuls, Atemfrequenz | Stress-Marker neben der Selbsteinschätzung; Wirkung von Atemübungen sichtbar |

Schreiben:

| Datentyp | Nutzen |
| --- | --- |
| Achtsamkeits-Minuten (`mindfulSession`) | Kopf-Training und Atemübungen zählen in Health |

## 3. Apple Watch (watchOS-Companion)

- **Check-in am Handgelenk**: zwei Taps, zehn Sekunden, auch unterwegs. Erhöht die Zahl der Messungen pro Tag deutlich.
- **Atemübung mit Haptik** am Handgelenk, ohne auf ein Display zu schauen.
- **Komplikation**: „Wie laut ist er gerade?“ als Einstieg.
- Liefert HRV, Lärm und Schlaf (siehe HealthKit).

## 4. AirPods-Sensorik

- **Kopfhörer-Erkennung** über `AVAudioSession.currentRoute`: Die App weiß, ob AirPods Pro, andere
  Bluetooth-Geräte oder Kabel angeschlossen sind, und wählt das passende Kalibrierprofil. Bei unbekanntem
  Gerät werden Messungen als „unkalibriert“ markiert.
- **Kopftracking** (`CMHeadphoneMotionManager`, AirPods Pro/Max/3. Gen): Nackenbeweglichkeit messen und
  Dehnübungen führen (Details in 06).
- **Hörgerätefunktion / Hörtest**: Die App startet sie nicht selbst (nicht möglich), führt aber per
  Deep-Link in die Einstellungen und liest das Ergebnis aus HealthKit.

Nicht möglich und daher nicht eingeplant: Geräuschunterdrückung oder Transparenzmodus steuern,
Apples adaptive Klanganpassung abschalten.

## 5. Erinnerungen und Ecological Momentary Assessment

- Lokale Benachrichtigungen (`UNUserNotificationCenter`) für Check-ins zu zufälligen Zeiten in
  Zeitfenstern (morgens, mittags, abends), wie in Forschungs-Apps. Zufall vermeidet Erwartungseffekte.
- Erinnerung an Reset-Sitzungen, Wochen-Check, Lektion des Tages.
- Respektiert Fokus-Modi; nachts keine Erinnerung.

## 6. Widgets, Live Activities, Kurzbefehle

- **Widget** auf Sperr- und Home-Screen: Check-in mit einem Tipp, Tagesfortschritt.
- **Live Activity / Dynamic Island** während einer Sitzung: Restzeit, Phase (Klang/Stille), Stopp.
- **App Intents**: „Hey Siri, starte Klanganreicherung für 30 Minuten“, „Wie laut ist mein Tinnitus“
  als Kurzbefehl, Automationen (z. B. beim Zubettgehen Klanganreicherung starten).

## 7. Core Haptics

- Atem-Pacing als Vibration (Einatmen: anschwellend, Ausatmen: abklingend), auch mit geschlossenen Augen.
- Taktile Rückmeldung im Residual-Inhibition-Labor beim Start der Bewertungsphase.

## 8. SwiftData + CloudKit

- Persistenz lokal, Sync über die private iCloud-Datenbank des Nutzers (iPhone ↔ Watch ↔ iPad).
- Kein eigener Server, keine Konten, Export als JSON weiterhin möglich.

## 9. Audio-Technik

- `AVAudioEngine` mit `AVAudioSourceNode` für Synthese (Ton, AM-Ton, Rauschen, CR-Takt) und
  `AVAudioUnitEQ` für Filter. Sample-genaues Timing ohne JavaScript-Jitter.
- Eigene Musik: lokale Dateien aus der Mediathek und „Dateien“ durch den Notch-Filter. Apple-Music-Streams
  sind DRM-geschützt und können nicht gefiltert werden; das wird in der App erklärt.

## 10. Barrierefreiheit und Systemintegration

- Dynamic Type, VoiceOver-Labels für alle Regler, „Bewegung reduzieren“ für Animationen.
- Dark/Light nach System, Fokus-Filter („Schlafen“ zeigt nur Klanganreicherung und Atemübung).

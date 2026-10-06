# 05 · Audio-Engine

## Graph

```
[Quellen] ──► [Formung] ──► [Pegel] ──► [Ohr-Routing] ──► [Limiter] ──► [Master] ──► Ausgang
                                                                        └──► [Analyser für Live-Spektrum]
```

- Quellen: `AVAudioSourceNode` (Ton, AM-Ton, Rauschen weiß/rosa/braun, CR-Sequenzer, Regen),
  `AVAudioPlayerNode` (eigene Musik).
- Formung: `AVAudioUnitEQ` mit Bändern für Bandpass (Schmalband), Hoch-/Tiefpass-Kaskaden (Notch),
  Peaking (AM-Anreicherung um f_T).
- Pegel: `AVAudioMixerNode` pro Stimme; Rampen von 20–600 ms gegen Klicks.
- Ohr-Routing: Stereo-Mixer mit Pan links/rechts/beide.
- Limiter: `AVAudioUnitEffect` (kAudioUnitSubType_PeakLimiter) plus harter Deckel im Master.
- Analyser: Tap auf dem Master, FFT 8192 über Accelerate/vDSP für das Live-Spektrum.

## Signal-Rezepte (identisch zur Web-App)

| Klang | Rezept |
| --- | --- |
| Reiner Ton | Sinus bei f_T |
| AM-Ton | Sinus bei f_T, 100 % Amplitudenmodulation mit 10 Hz, RMS-Ausgleich ×1,22 |
| Schmalband ⅓ / 1 Oktave | Weißes Rauschen → 2 kaskadierte Bandpässe, Q aus Bandbreite, Makeup-Gain |
| Breitband | Weißes Rauschen |
| Notch | Parallel: Tiefpass bei f_T·2^(−w/2) und Hochpass bei f_T·2^(w/2), je 8. Ordnung Butterworth (4 Biquads, Q 0,5098 / 0,6013 / 0,8999 / 2,5629), Summe. Ziel: 0 dB Passband, −3 dB an den Kanten, ≈ −24 dB in der Mitte |
| AM-Anreicherung | Rosa Rauschen → Peaking-Filter +9 dB, Q 0,7 bei f_T → 10-Hz-AM mit 40 % Tiefe |
| Regen | Rosa Rauschen → Hochpass 400 Hz → langsame Pegelmodulation 0,13 Hz |
| CR | 4 Töne bei 0,766 / 0,9 / 1,1 / 1,395 · f_T, Zyklus 1,5 Hz, je Zyklus zufällige Reihenfolge, 3 Zyklen an / 2 aus, Tonlänge 150 ms mit 10-ms-Rampen, sample-genau im Render-Callback geplant |

Die Koeffizienten werden in `TinnitusCore/Signal` berechnet (reine Funktionen) und in Tests gegen
die Soll-Antwort geprüft.

## Kalibrierung und Geräteprofile

Problem: Die Web-App kennt nur relative Pegel (dBFS). Für vergleichbare Messungen und sichere Deckel
brauchen wir dB SPL am Trommelfell, zumindest geschätzt.

Ansatz:

1. **Geräteerkennung** über `AVAudioSession.currentRoute.outputs` (Port-Typ, Port-Name). Profile:
   AirPods Pro 2, AirPods Pro 3, AirPods 4, AirPods Max, generisches Bluetooth, Kabel, Lautsprecher (gesperrt für Messungen).
2. **Profil = Empfindlichkeitskurve** dB SPL pro dBFS je Terzband 250 Hz–16 kHz. Für AirPods-Modelle aus
   Messungen am Kunstkopf (einmalig mit Messmikrofon erstellen oder aus publizierten Messungen ableiten);
   oberhalb 8 kHz mit großem Unsicherheitsband, weil Sitz im Ohr dominiert.
3. **Plausibilisierung** über HealthKit `headphoneAudioExposure`: iOS schätzt für Apple-Kopfhörer die
   Kopfhörer-Dosis in dBA. Die App vergleicht ihre eigene Pegelschätzung über eine Sitzung mit diesem
   Wert und korrigiert den Profil-Offset in engen Grenzen (±3 dB).
4. **Unkalibrierte Geräte**: Messungen werden gespeichert, aber als „relativ“ markiert; Verlaufsvergleiche
   nur innerhalb desselben Geräts.
5. **Nutzer-Kalibrierung light**: Hörschwelle bei 1 kHz als Anker (Hughson-Westlake) und Vergleich mit
   dem Audiogramm aus HealthKit, wenn vorhanden. Daraus ein individueller Offset.

## Hörschutz

- Harter Deckel: kein Signal über geschätzt 85 dB SPL; Messsignale (RI-Stimuli) maximal MML + 15 dB
  und nie über 80 dB SPL; Dauer über 75 dB SPL auf 5 Minuten pro Durchgang begrenzt.
- Dosis-Zähler pro Tag aus eigenem Pegel × Zeit (Äquivalent zur WHO-Wochendosis), Warnung bei 50 %.
- Nach Systemlautstärke-Änderung während einer Sitzung: Neuberechnung, ggf. automatisches Absenken.
- Lautsprecher-Ausgabe: nur Klanganreicherung erlaubt, keine Messungen.

## Hintergrund und Unterbrechungen

- Session-Kategorie `.playback`, Modus `.default`, Option `.mixWithOthers` nur für Klanganreicherung.
- Interruptions (Anruf, Siri): pausieren, nach Ende automatisch weiter bei Klanganreicherung, nicht bei Messungen.
- Route-Change (Kopfhörer abgezogen): sofort pausieren, Profil neu laden, Nutzer informieren.
- Now-Playing-Infos und Remote-Commands (Play/Pause/Stop, kein Skip).

## Eigene Musik

- Quellen: `MPMediaLibrary` (nur Titel ohne DRM, `assetURL != nil`) und Dateien-App (`UIDocumentPicker`).
- Dekodierung über `AVAudioFile` → `AVAudioPlayerNode` → Notch-Kette.
- Hinweis in der App, warum Apple-Music-Streams nicht gefiltert werden können.

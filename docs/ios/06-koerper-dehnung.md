# 06 · Körper-Modul: Dehnung, Mobilisation, Kiefer

## Sollten Dehnübungen rein? Ja, mit klarer Begründung und Grenzen.

Evidenz:

- Etwa zwei Drittel der Betroffenen können ihren Tinnitus über Kiefer- oder Nackenbewegungen
  verändern (Sanchez et al. 2002). Für diese Gruppe gibt es Konsens-Kriterien für „somatischen Tinnitus“
  (Michiels et al. 2018).
- Eine randomisierte Studie zeigte, dass Physiotherapie der Halswirbelsäule bei somatischem Tinnitus
  die Beschwerden senkt (Michiels et al. 2016, Manual Therapy). Behandlung von Kiefergelenksbeschwerden
  (CMD) reduziert Tinnitus bei Betroffenen mit CMD (mehrere systematische Übersichten).
- Für Menschen ohne somatische Komponente gibt es keinen Beleg, dass Dehnen den Tinnitus leiser macht.
  Als Entspannungs- und Stressbaustein ist es trotzdem sinnvoll und harmlos.

Konsequenz für die App:

- Das Körper-Modul ist **für alle** als Entspannung verfügbar und wird **für Nutzer mit positivem
  Somatik-Check** im Programm priorisiert (tägliche Aufgabe statt optional).
- Die App ersetzt keine Physiotherapie. Bei positivem Somatik-Check empfiehlt sie ausdrücklich eine
  physiotherapeutische oder zahnärztliche (CMD) Abklärung; in Deutschland auf Rezept möglich.
- Kontraindikationen werden vor dem ersten Start abgefragt: akute Nackenschmerzen, Bandscheibenvorfall,
  Schwindel bei Kopfbewegung, frische Verletzung, Kieferblockade. Dann nur die sanften Übungen.

## Programm

Zwei Programme, jeweils 8–10 Minuten, gern morgens und abends:

### A · Nacken und Schultern

| # | Übung | Dauer | Ziel |
| --- | --- | --- | --- |
| 1 | Schulterkreisen rückwärts | 30 s | Aufwärmen, Schultern senken |
| 2 | Kinn einziehen (Chin Tuck), 10× halten 5 s | 60 s | Tiefe Nackenbeuger aktivieren, Kopfvorhaltung korrigieren |
| 3 | Seitneigung mit leichtem Handzug, je Seite | 2 × 30 s | Oberer Trapezius |
| 4 | Blick zur Achsel mit leichtem Handzug, je Seite | 2 × 30 s | Levator scapulae |
| 5 | Rotation und leichtes Anheben des Kinns, je Seite | 2 × 30 s | Sternocleidomastoideus (häufiger Tinnitus-Triggerpunkt) |
| 6 | Isometrisches Halten: Hand gegen Stirn/Hinterkopf/Schläfe, je 5 s | 60 s | Stabilisierung, bewusste Entspannung danach |
| 7 | Brustöffner an Wand oder Türrahmen | 45 s | Gegenspieler der Vorhaltung |
| 8 | Nachspüren, 3 Atemzüge | 30 s | Abschluss |

### B · Kiefer und Gesicht

| # | Übung | Dauer | Ziel |
| --- | --- | --- | --- |
| 1 | Ruheposition: Zunge am Gaumen, Zähne auseinander, Lippen zu (6 Atemzüge) | 45 s | Grundhaltung gegen Pressen |
| 2 | Mund kontrolliert öffnen mit Zungenspitze am Gaumen, 6× | 60 s | Rocabado 6×6, geführte Öffnung |
| 3 | Kaumuskel-Selbstmassage (Masseter) mit kreisenden Fingern, je Seite | 2 × 45 s | Tonus senken |
| 4 | Schläfenmuskel-Massage (Temporalis) | 45 s | Tonus senken |
| 5 | Kiefer locker seitlich pendeln | 30 s | Mobilisation |
| 6 | Isometrisch: Hand unter Kinn, leicht gegen Öffnen, 5× 5 s | 45 s | Koordination |
| 7 | Gesicht „auswringen und loslassen“ (Mimik anspannen, 5 s, lösen) 3× | 45 s | Kontrast-Entspannung |
| 8 | Nachspüren mit Ruheposition | 30 s | Abschluss |

Jede Übung hat: Titel, Zielmuskel, Ausführung in 2–3 Sätzen, Fehlerbild („nicht die Schulter hochziehen“),
Timer, Animation.

## Animationstechnik

Drei Optionen, Empfehlung fett:

1. **SwiftUI-Vektorfigur mit Keyframe-Animation (MVP).** Eine stilisierte Figur (Kopf, Hals, Schultern,
   Hände) aus `Path`-Formen, Gelenkwinkel als animierbare Parameter (`KeyframeAnimator`, iOS 17+).
   Vorteile: keine Abhängigkeit, Theme-Farben, „Bewegung reduzieren“ trivial, Figur kann live die
   Soll-Position mit der Ist-Position aus dem Kopftracking überlagern. Nachteil: schematisch.
2. **Rive** (`RiveRuntime`): State-Machines, Eingaben wie Winkel oder Phase von außen steuerbar,
   kleine Dateien, hochwertiger Look. Gute Wahl, wenn ein Designer die Figur baut.
3. **Lottie** (`lottie-ios`): verbreitet, aber Steuerung von außen (Winkel aus Tracking) ist umständlich.

**Empfehlung:** Phase 1 mit SwiftUI-Vektorfigur (schnell, steuerbar, konsistent). Phase 3 Austausch der
Figur durch Rive-Assets, die Schnittstelle (Gelenkwinkel als Eingaben) bleibt gleich.

## Kopftracking mit AirPods (Innovation mit echtem Nutzen)

`CMHeadphoneMotionManager` liefert Orientierung des Kopfes (Pitch/Roll/Yaw) von AirPods Pro, AirPods Max
und AirPods 3/4. Damit:

- **Messung der Beweglichkeit** im Somatik-Check: maximale Rotation links/rechts, Seitneigung, Flexion/
  Extension in Grad. Basiswert und Verlauf über Wochen (Verlaufs-Chart).
- **Geführte Dehnung**: Die Figur zeigt die Zielposition, ein Ring füllt sich, wenn der Nutzer sie
  erreicht und hält; sanftes Haptik-Signal bei Zielwinkel; Warnung bei Ruck oder Überstrecken.
- **Haltungs-Hinweis**: Während Klangsitzungen am Schreibtisch kann die App optional eine
  Kopfvorhaltung erkennen (Pitch über Schwelle über Minuten) und still erinnern.
- Ohne AirPods funktioniert alles auch mit Timer, nur ohne Rückmeldung.

Grenzen: Yaw driftet über Zeit (Referenz zu Beginn jeder Übung neu setzen); keine Absolutposition.

## Verknüpfung mit dem Rest der App

- Positiver Somatik-Check → Körper-Programm wird Tagesaufgabe, Verlauf zeigt Beweglichkeit und Lautheit
  gemeinsam. Das erlaubt die persönliche Frage: Wird der Tinnitus leiser, wenn der Nacken beweglicher wird?
- Lektion 5 (Muskeln lösen) verlinkt direkt ins Kiefer-Programm.
- Abend-Routine (Kurzbefehl): Kiefer-Programm → Atemübung → Klanganreicherung mit Sleep-Timer.

# Tinnitus Lab

Eine installierbare Web-App (Mac, iPhone/iPad, jeder moderne Browser) für ein strukturiertes
Selbst-Experiment gegen chronischen, hochfrequenten Tinnitus. Keine Server, keine Konten:
alle Daten bleiben im Browser des Geräts.

## Was die App macht

| Schritt | Modul | Zweck |
| --- | --- | --- |
| Messen | **Tinnitus-Matching** | Frequenz (3 unabhängige Durchgänge, Oktaven-Check, Median), Klangfarbe, Lautheit, minimale Maskierungsschwelle (MML), pro Ohr |
| Messen | **Hörprofil** | Relativer Schwellen-Test 500 Hz – 16 kHz pro Ohr, zeigt den Hochton-Abfall und die Lage des Tinnitus im Hörprofil |
| Analysieren | **Residual-Inhibition-Labor** | Testet systematisch fünf Stimuli (Ton, ⅓-Oktave-Schmalband, 1-Oktave-Schmalband, Breitband, Notched) auf Tiefe und Dauer der Nach-Unterdrückung und erstellt eine Rangliste |
| Therapieren | **Reset-Sitzung** | Zyklen aus deinem wirksamsten RI-Klang und Stille |
| Therapieren | **Notched Sound** | Rauschen, Regen oder eigene Musikdatei durch einen 8. Ordnung Butterworth-Bandstop (Standard 1 Oktave) um die Tinnitus-Frequenz |
| Therapieren | **CR-Neuromodulation** | Vier Töne (0,766 / 0,9 / 1,1 / 1,395 × f_T), zufällige Reihenfolge, 1,5 Hz, 3 Zyklen an / 2 aus (Tass et al. 2012) |
| Therapieren | **Klanganreicherung** | Leiser Hintergrundklang am „Mixing Point“ unterhalb der MML |
| Therapieren | **Bimodal (experimentell)** | Klangimpulse auf f_T gekoppelt mit Vibrationsimpulsen (wo die Vibration-API verfügbar ist) |
| Verfolgen | **Tagebuch & Wochen-Check** | Lautheit, Belastung, Schlaf, Stress, Auslöser; Trend, Korrelationen, Sofort-Effekt je Modus |
| Wissen | **Evidenz-Seite** | Ehrliche Einordnung der Verfahren, 8-Wochen-Protokoll, Gehörschutz, Warnzeichen |

## Entwicklung

```bash
npm install
npm run dev        # http://localhost:5173, --host für Zugriff vom iPhone im WLAN
npm run build      # Typecheck + Produktions-Build nach dist/
npm run preview
```

Vite + TypeScript, keine Laufzeit-Abhängigkeiten. Audio über die Web Audio API
(Oszillatoren, Rausch-Buffer, Biquad-Kaskaden, AudioContext-Scheduling für CR), Persistenz über
localStorage, Service Worker für Offline-Betrieb, PWA-Manifest für den Home-Bildschirm.

## Installation auf dem Gerät

Den Inhalt von `dist/` auf irgendeinen statischen Host legen (GitHub Pages, Netlify, eigener
Webserver) oder lokal `npm run preview --host` starten und vom iPhone aus öffnen.

- iPhone/iPad: Safari → Teilen → „Zum Home-Bildschirm“
- Mac: Safari → Ablage → „Zum Dock hinzufügen“, oder Chrome/Edge → Installieren-Symbol

## Wichtige Hinweise

- Alle Pegel sind relativ (0 dB = Vollaussteuerung × Master-Lautstärke), nicht kalibriert.
  Ein Limiter und ein Master-Cap schützen vor Pegelspitzen, aber die Lautstärke am Gerät muss
  trotzdem vernünftig eingestellt sein.
- Die App ersetzt keine HNO-ärztliche Abklärung. Ein aktuelles Audiogramm ist nach langjährigem
  Lärm-Tinnitus sinnvoll, weil Hochton-Hörverlust die Therapiewahl beeinflusst (Hörgeräte).
- Chronischer Tinnitus ist nach aktuellem Stand nicht heilbar. Die App hilft, die Verfahren
  zu finden und konsequent anzuwenden, die bei dir individuell die Lautheit oder die Belastung senken.

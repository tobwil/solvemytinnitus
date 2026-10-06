# Sprachaufnahmen für die Anleitungen

Alle Sätze, die die App vorliest (Übungs-Cues, Rhythmus-Ansagen, geführte Schritte), sind fest. Sie werden
einmal mit einer neuronalen Stimme **lokal auf dem Mac** aufgenommen und als AAC in der App ausgeliefert
(`TinnitusLab/Resources/Voice/<key>.m4a`, zusammen ca. 1–2 MB). Zur Laufzeit läuft kein Modell; die Systemstimme
ist nur Rückfall für Texte ohne Aufnahme.

- Quelle der Sätze: `VoicePrompts.all` in `TinnitusCore` (exportiert mit `swift run voice-prompts`)
- Dateiname: die ersten 16 Hex-Zeichen von SHA-256 über den Text → ändert sich ein Text, wird er neu aufgenommen
- Test `everySpokenPhraseHasARecording` schlägt fehl, wenn nach einer Inhaltsänderung Aufnahmen fehlen

## Einrichten

```bash
uv venv -p 3.12 .venv && source .venv/bin/activate   # oder python3.12 -m venv
pip install -r ios/Scripts/voice/requirements.txt
```

## Aufnehmen

```bash
python ios/Scripts/voice/generate.py                 # nur fehlende/geänderte Sätze, entfernt verwaiste Dateien
python ios/Scripts/voice/generate.py --force         # alles neu
python ios/Scripts/voice/generate.py --samples /tmp/voice   # Vergleich Piper vs. Chatterbox
python ios/Scripts/voice/generate.py --reference meine-stimme.wav   # eigene Referenzstimme (5–15 s, deutsch)
```

## Modelle und Lizenzen

| Teil | Lizenz | Rolle |
| --- | --- | --- |
| [Chatterbox Multilingual](https://github.com/resemble-ai/chatterbox) (Resemble AI) | MIT | Sprachmodell (natürliche Betonung) |
| Piper-Stimme `de_DE-thorsten-high` ([Thorsten-Datensatz](https://www.thorsten-voice.de)) | CC0 | Klangfarbe der Referenz, Rückfall-Engine |
| [Piper](https://github.com/OHF-Voice/piper1-gpl) / espeak-ng | GPL-3.0 | nur Werkzeug zur Erzeugung, nicht Teil der App |

Die erzeugten Audiodateien enthalten keinen Code dieser Werkzeuge. Chatterbox versieht seine Ausgaben mit einem
unhörbaren Wasserzeichen (Perth), das KI-erzeugte Sprache kenntlich macht.

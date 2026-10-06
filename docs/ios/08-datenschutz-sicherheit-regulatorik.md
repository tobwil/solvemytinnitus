# 08 · Datenschutz, Hörschutz, Regulatorik

## Datenschutz

- Alle Daten lokal (SwiftData) und optional in der privaten iCloud-Datenbank des Nutzers (CloudKit).
  Kein eigener Server, keine Analytics-SDKs, keine Werbe-IDs.
- HealthKit: Zugriff nur je Datentyp nach Einwilligung, Begründung im Dialog verständlich formuliert,
  Daten werden nie das Gerät/iCloud verlassen. Apple verlangt dafür eine Datenschutzerklärung und
  verbietet Nutzung von Health-Daten für Werbung.
- Export: JSON (kompatibel mit Web-App) und PDF, ausgelöst nur vom Nutzer.
- App-Store-Datenschutzlabel: „Daten werden nicht erfasst“.

## Hörschutz (technisch verbindlich)

- Pegel-Deckel wie in 05: max. 85 dB SPL geschätzt, Messsignale max. 80 dB SPL, zeitlich begrenzt.
- Tagesdosis-Zähler mit Warnung; Hinweis auf WHO-Empfehlung.
- Lautsprecher-Ausgabe für Messungen gesperrt.
- Onboarding erklärt: leise ist wirksam und sicher.

## Medizinische Sicherheit

- Warnzeichen-Screen (plötzliche Veränderung, einseitig neu, pulssynchron, Hörsturz, Schwindel) im
  Onboarding und im Wissen; bei entsprechender Eingabe im Tagesrückblick Hinweis auf ärztliche Abklärung.
- Körper-Modul mit Kontraindikations-Abfrage.
- Kopf-Training ist Psychoedukation und Selbsthilfe, keine Psychotherapie; Hinweis auf professionelle
  Hilfe bei hoher Belastung (Wochen-Check-Score dauerhaft hoch) mit Nummern der Telefonseelsorge.

## Regulatorische Abgrenzung (Deutschland/EU)

- Version 1 wird **kein Medizinprodukt**. Entscheidend ist die Zweckbestimmung: Die App dient der
  Selbstbeobachtung, Entspannung, Wissensvermittlung und dem persönlichen Ausprobieren von Klängen.
  Sie stellt keine Diagnose und behauptet keine Behandlung einer Krankheit.
- Daraus folgende Regeln für Texte und Features:
  - Keine Aussagen wie „behandelt Tinnitus“, „reduziert Tinnitus nachweislich“, „Therapie“ als
    Produktbezeichnung. Zulässig: „Klangprogramme zum Ausprobieren“, „Training“, „Übungen“, „Messen,
    was bei dir wirkt“.
  - Das Hörprofil ist ein „Hörcheck“, kein Audiogramm im klinischen Sinn; MML und Spektrum sind
    „Messungen für dein Profil“.
  - Evidenztexte dürfen Studien zitieren, aber keine Wirkung der App selbst behaupten.
- Wenn später eine **DiGA** oder ein CE-gekennzeichnetes Medizinprodukt angestrebt wird: Klasse IIa unter
  MDR (Software mit Entscheidungsunterstützung zu Therapie), Qualitätsmanagement nach ISO 13485,
  klinische Bewertung, Benannte Stelle, danach BfArM-Fast-Track. Das ist ein eigenes Projekt und sollte
  erst nach belastbaren Nutzerdaten aus Version 1 entschieden werden.
- App Store Review: Health-Apps mit Audiofunktionen benötigen klare Hinweise zu Lautstärke und dürfen
  keine Falschaussagen zu Gesundheit machen (Guideline 1.4.1, 5.1.3).

## Qualitätssicherung

- Jede Änderung an Pegeln, Filtern oder Deckeln braucht einen Offline-Rendering-Test.
- Inhalte (Lektionen, Evidenz, Dehnübungen) werden einmal von einer Fachperson (HNO/Audiologie,
  Psychotherapie, Physiotherapie) gegengelesen, bevor die App öffentlich wird.
- Beta mit Betroffenen, Fokus: Verständlichkeit, Lautstärke-Gefühl, Nutzbarkeit nachts.

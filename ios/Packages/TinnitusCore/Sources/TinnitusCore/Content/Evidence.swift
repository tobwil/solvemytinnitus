import Foundation

public struct EvidenceItem: Sendable, Identifiable, Hashable {
    public var title: String
    public var level: EvidenceLevel
    public var verdict: String
    public var text: String
    public var refs: String
    public var inApp: String?
    public var id: String { title }
}

public struct EvidenceGroup: Sendable, Identifiable, Hashable {
    public var title: String
    public var items: [EvidenceItem]
    public var id: String { title }
}

public struct NextStep: Sendable, Identifiable, Hashable {
    public var symbol: String
    public var title: String
    public var text: String
    /// Deep link (settings, DiGA directory).
    public var link: URL?
    public var linkLabel: String?
    public var id: String { title }
}

public enum EvidenceContent {
    /// Literature status of the content. Shown in the app.
    public static let asOf = "Oktober 2026"

    public static let summary = [
        "Eine Heilung für chronischen Lärm-Tinnitus gibt es derzeit nicht, auch kein zugelassenes Medikament.",
        "**Am besten belegt ist kognitive Verhaltenstherapie;** bei Hörverlust kommen Hörgeräte dazu (von der Leitlinie empfohlen). Beide senken die Belastung verlässlicher als jedes Klangprogramm – die Lautheit selbst ändert sich meist wenig.",
        "Die meisten Klangverfahren wirken im Einzelfall, aber nicht im Durchschnitt. Darum misst diese App, was bei dir wirkt, statt es zu versprechen.",
    ]

    public static let groups: [EvidenceGroup] = [
        EvidenceGroup(title: "Nachweislich wirksam", items: [
            EvidenceItem(title: "Kognitive Verhaltenstherapie", level: .strong, verdict: "senkt die Belastung, nicht die Lautheit",
                         text: "Am besten belegtes Verfahren. In der großen europäischen UNITI-Studie hatten CBT allein und Hörgeräte allein die größten Effekte; Kombinationen waren nur etwas besser. Internetbasierte Programme wirken ähnlich.",
                         refs: "Fuller et al. 2020, Cochrane; Schoisswohl et al. 2025, Nat Commun (UNITI, n=461); Sattel et al. 2025", inApp: "Kopf-Training"),
            EvidenceItem(title: "Hörgeräte bei Hörverlust", level: .moderate, verdict: "leitlinienempfohlen, Studienlage mäßig",
                         text: "Ersetzen den fehlenden Input, an dem der Tinnitus hängt. Konventionell angepasst; eine zusätzliche „Notch“ im Hörgerät brachte in Studien keinen Vorteil. Auch bei normalem Standard-Audiogramm sind die Schwellen über 10 kHz bei Tinnitus oft erhöht. AirPods Pro haben eine Hörgerätefunktion für leichten bis mittleren Hörverlust.",
                         refs: "Mazurek et al. 2022, S3-Leitlinie; Sereda et al. 2018, Cochrane; Schiele et al. 2025, Ear Hear; Waechter et al. 2026; Jafari et al. 2022", inApp: "Hörcheck bis 16 kHz, Import aus Apples Hörtest"),
        ]),
        EvidenceGroup(title: "Vielversprechend, noch nicht gesichert", items: [
            EvidenceItem(title: "Bimodale Neuromodulation", level: .moderate, verdict: "konsistenteste Gerätedaten",
                         text: "Lenire (Klang plus Zungenstimulation) ist seit 2023 in den USA zugelassen und in Deutschland privat erhältlich. Große Verbesserungen in den Studien, aber ohne echte Placebo-Gruppe; der Vorteil gegenüber Klang allein zeigte sich nur bei mittel- bis schwergradigem Tinnitus. Das Michigan-Gerät (Klang plus Wange/Nacken) half in einer kontrollierten Studie bei somatischem Tinnitus, ist aber nicht auf dem Markt.",
                         refs: "Conlon et al. 2020/2022; Boedts et al. 2024, Nat Commun (TENT-A3); Jones et al. 2023, JAMA Netw Open; Kitsis et al. 2026, Laryngoscope", inApp: "Somatik-Check"),
            EvidenceItem(title: "Physiotherapie bei somatischem Tinnitus", level: .moderate, verdict: "eine RCT, mehrere Übersichten",
                         text: "Etwa zwei Drittel der Betroffenen können ihren Tinnitus über Kiefer oder Nacken verändern. Physiotherapie der Halswirbelsäule senkte in einer randomisierten Studie die Beschwerden bei somatischem Tinnitus; Behandlung von Kiefergelenksbeschwerden (CMD) hilft Betroffenen mit CMD. Ohne somatische Komponente kein Beleg für eine Wirkung auf den Tinnitus, aber als Entspannung sinnvoll.",
                         refs: "Sanchez et al. 2002; Michiels et al. 2016, Manual Therapy; Michiels et al. 2018 (Konsens-Kriterien)", inApp: "Körper-Programme"),
            EvidenceItem(title: "Personalisierte AM-Klanganreicherung", level: .weak, verdict: "eine Studie, nicht randomisiert",
                         text: "10-Hz-amplitudenmoduliertes Rauschen senkte über 6 Monate die Maskierungsschwelle stärker als unmoduliertes. Wer Residual Inhibition zeigt, sprach besser auf Klanganreicherung an.",
                         refs: "Sendesen et al. 2026, Hear Res (n=71); Sendesen et al. 2024", inApp: "Klanganreicherung · AM 10 Hz"),
            EvidenceItem(title: "Dekorrelierender Klang", level: .experimental, verdict: "neu, sehr kleine Studie",
                         text: "Ein Klang, der die Kopplung zwischen Frequenzbereichen stört, senkte in einer verblindeten Online-Studie die Lautheit, Placebo-Klang nicht. Erste Daten, noch nicht repliziert.",
                         refs: "Yukhnovich, Sedley et al. 2025, Hear Res (n=53)"),
            EvidenceItem(title: "Vagusnerv-Stimulation (auch am Ohr)", level: .weak, verdict: "bescheidene Effekte",
                         text: "Gepaart mit Tönen; Meta-Analysen finden kleine Verbesserungen der Belastung, aber keinen Effekt auf die Lautheit. Neuere Studien mit Ohr-Stimulatoren ohne Gruppenunterschied.",
                         refs: "Tyler et al. 2017; Fernández-Hernando et al. 2023; Deng et al. 2026"),
        ]),
        EvidenceGroup(title: "Kurzfristig wirksam, langfristig offen", items: [
            EvidenceItem(title: "Residual Inhibition", level: .weak, verdict: "zuverlässiger Kurzzeiteffekt",
                         text: "Schmalband-Rauschen im Bereich von Hörverlust und Tinnitus unterdrückt am häufigsten, aber sehr individuell. Dass wiederholte Unterdrückung dauerhaft wirkt, zeigt bisher keine kontrollierte Studie.",
                         refs: "Roberts et al. 2008, JARO; Neff et al. 2017/2019; Schoisswohl et al. 2025, JARO", inApp: "RI-Labor, Reset-Sitzung"),
            EvidenceItem(title: "Klanganreicherung allgemein", level: .weak, verdict: "hilft vielen subjektiv",
                         text: "Nimmt der Stille den Kontrast, hilft beim Einschlafen. Als alleinige Maßnahme schwach belegt. Im Alltag reduzieren Umgebungsgeräusche den Tinnitus bei etwa jedem Fünften und verstärken ihn bei wenigen.",
                         refs: "Kraft et al. 2025, npj Digit Med (67 442 Messungen)", inApp: "Klanganreicherung"),
        ]),
        EvidenceGroup(title: "Nicht besser als Placebo", items: [
            EvidenceItem(title: "Notched Music", level: .weak, verdict: "widersprüchlich",
                         text: "Frühe Studien positiv, neuere Meta-Analysen finden keinen Vorteil gegenüber unveränderter Musik.",
                         refs: "Okamoto et al. 2010; Alfonso et al. 2024; Tavanai et al. 2024; Jiang et al. 2025", inApp: "Notched Sound"),
            EvidenceItem(title: "Akustische CR-Neuromodulation", level: .experimental, verdict: "große Studie negativ",
                         text: "Die doppelblinde RESET2-Studie fand keinen Unterschied zur Placebo-Stimulation.",
                         refs: "Hall et al. 2022, Brain Sci (n=100)", inApp: "CR-Neuromodulation"),
            EvidenceItem(title: "Medikamente und Regeneration", level: .experimental, verdict: "nichts zugelassen",
                         text: "OTO-313 und FX-322 scheiterten in Phase 2; Medikamenten-Kombinationen waren nicht besser als Placebo. Für Lärm-Tinnitus oder Synaptopathie gibt es keine zugelassene Medikamenten- oder Gentherapie. Vorsicht bei Nahrungsergänzungsmitteln mit Heilsversprechen.",
                         refs: "Searchfield et al. 2023; Abouzari et al. 2025"),
            EvidenceItem(title: "rTMS und tDCS", level: .experimental, verdict: "gepoolt nicht signifikant",
                         text: "Hirnstimulation von außen zeigt in der Zusammenschau keine verlässliche Wirkung.",
                         refs: "Kitsis et al. 2026, Laryngoscope (26 RCTs)"),
        ]),
    ]

    public static let nextSteps: [NextStep] = [
        NextStep(symbol: "ear", title: "HNO-Termin mit Hochton-Audiogramm",
                 text: "Tonaudiogramm bis 16 kHz, Abklärung anderer Ursachen. Bei Hörverlust: Hörgeräte-Versorgung, die Kasse zahlt bei Indikation. Apples Hörtest mit AirPods Pro liefert eine erste Einschätzung bis 8 kHz.",
                 link: nil, linkLabel: nil),
        NextStep(symbol: "brain.head.profile", title: "Kognitive Therapie auf Rezept",
                 text: "Tinnitus-Apps als DiGA (z. B. Kalmeda) kann dein Arzt kostenlos verordnen. Alternativ tinnitusspezifische Psychotherapie.",
                 link: URL(string: "https://diga.bfarm.de/de/verzeichnis"), linkLabel: "DiGA-Verzeichnis öffnen"),
        NextStep(symbol: "figure.cooldown", title: "Physiotherapie oder CMD-Abklärung",
                 text: "Wenn dein Somatik-Check positiv ist: Physiotherapie (Halswirbelsäule) oder zahnärztliche Abklärung auf CMD. In Deutschland auf Rezept möglich.",
                 link: nil, linkLabel: nil),
        NextStep(symbol: "waveform.path.ecg", title: "Bimodale Therapie prüfen",
                 text: "Bei mittel- bis schwergradiger Belastung trotz CBT: Lenire als Selbstzahler-Option mit einem HNO besprechen. Wirkung bei leichtem Tinnitus kaum nachweisbar.",
                 link: nil, linkLabel: nil),
        NextStep(symbol: "shield", title: "Gehörschutz",
                 text: "Gefilterte Ohrstöpsel bei Konzerten und Lärm. Nicht im Alltag, sonst wird das Gehör empfindlicher.",
                 link: nil, linkLabel: nil),
    ]

    public static let howTheAppUsesResearch: [(String, String)] = [
        ("Likeness-Spektrum statt Regler", "Bei hohem Tinnitus deutlich reproduzierbarer (84 % vs. 23 % der Patienten, Hébert 2018)."),
        ("Verblindete Tests", "Die Erwartung beeinflusst Tinnitus-Bewertungen stark; Medikamentenstudien scheiterten oft am Placebo-Effekt. Darum testet das RI-Labor verblindet."),
        ("Mehrfach-Check-ins zu zufälligen Zeiten", "Tinnitus schwankt im Tagesverlauf, Auslöser sind individuell (TrackYourTinnitus-Studien). Mehrere Messungen pro Tag sind aussagekräftiger als eine."),
        ("Ehrliche Kennzeichnung", "Jedes Verfahren zeigt seine Evidenz. Schwach belegte Verfahren sind enthalten, weil sie einzelnen Menschen helfen können, aber nicht als Versprechen."),
    ]
}

public enum SafetyContent {
    /// Red flags requiring prompt medical evaluation (onboarding, knowledge, daily review).
    public static let redFlags = [
        "Plötzliche, deutliche Veränderung des Tinnitus",
        "Neu und nur auf einem Ohr",
        "Pulsierend im Rhythmus des Herzschlags",
        "Plötzlicher Hörverlust (Hörsturz)",
        "Schwindel oder Gleichgewichtsstörungen",
    ]

    public static let redFlagCallout = "Warnzeichen für eine zeitnahe ärztliche Abklärung: plötzliche Veränderung, neu einseitig, pulsierend im Herzschlag, Hörsturz, Schwindel."

    public static let disclaimer = "Kein Medizinprodukt. Ersetzt keine HNO-ärztliche Abklärung."

    /// Telefonseelsorge Deutschland (24 h, kostenlos).
    public static let crisisNumbers = ["0800 111 0 111", "0800 111 0 222", "116 123"]

    /// Weekly score that, if it stays high, triggers a referral hint.
    public static let highDistressScore = 60
}

public enum WeeklyContent {
    public static let questions = [
        "Wie oft hast du den Tinnitus bewusst wahrgenommen?",
        "Wie stark hat er Ein- oder Durchschlafen gestört?",
        "Wie stark hat er deine Konzentration beeinträchtigt?",
        "Wie sehr hat er dich verärgert oder gestresst?",
        "Wie sehr hast du ruhige Situationen gemieden?",
        "Wie stark hat er Gespräche oder Hören gestört?",
        "Wie entmutigt hast du dich wegen des Tinnitus gefühlt?",
        "Wie stark hat er deine Lebensqualität beeinträchtigt?",
    ]
    public static let scale = ["Gar nicht", "Wenig", "Mäßig", "Stark", "Extrem"]

    public static func score(_ answers: [Int]) -> Int {
        Int((Double(answers.reduce(0, +)) / Double(4 * questions.count) * 100).rounded())
    }
}

public struct ManeuverInfo: Sendable, Identifiable, Hashable {
    public var id: SomaticManeuver
    public var title: String
    public var how: String
    public var symbol: String
}

public enum SomaticContent {
    public static let maneuvers: [ManeuverInfo] = [
        ManeuverInfo(id: .clench, title: "Zähne fest zusammenbeißen", how: "Beiße die Backenzähne kräftig aufeinander.", symbol: "rectangle.compress.vertical"),
        ManeuverInfo(id: .jawForward, title: "Unterkiefer nach vorn", how: "Schieb den Unterkiefer so weit wie möglich nach vorn.", symbol: "arrow.right.circle"),
        ManeuverInfo(id: .jawOpen, title: "Mund weit öffnen", how: "Öffne den Mund so weit es angenehm geht.", symbol: "arrow.up.and.down.circle"),
        ManeuverInfo(id: .headForward, title: "Stirn gegen die Hand", how: "Hand an die Stirn, Kopf kräftig nach vorn drücken, ohne dass er sich bewegt.", symbol: "hand.raised"),
        ManeuverInfo(id: .headBack, title: "Hinterkopf gegen die Hand", how: "Hand an den Hinterkopf, Kopf kräftig nach hinten drücken.", symbol: "hand.raised"),
        ManeuverInfo(id: .headLeft, title: "Kopf nach links gegen die Hand", how: "Linke Hand an die linke Schläfe, Kopf dagegen drücken.", symbol: "hand.raised"),
        ManeuverInfo(id: .headRight, title: "Kopf nach rechts gegen die Hand", how: "Rechte Hand an die rechte Schläfe, Kopf dagegen drücken.", symbol: "hand.raised"),
        ManeuverInfo(id: .gaze, title: "Blick ganz zur Seite", how: "Schau ohne Kopfbewegung so weit wie möglich nach links, dann nach rechts.", symbol: "eye"),
    ]

    public static func info(_ m: SomaticManeuver) -> ManeuverInfo { maneuvers.first { $0.id == m }! }
}

import Foundation

/// Evidence level 1–4 shown next to every procedure.
public enum EvidenceLevel: Int, Sendable, Comparable, CaseIterable {
    case experimental = 1, weak, moderate, strong
    public var label: String {
        switch self {
        case .experimental: "Experimentell"
        case .weak: "Schwach"
        case .moderate: "Mittel"
        case .strong: "Stark"
        }
    }
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public struct StimulusInfo: Sendable, Identifiable, Hashable {
    public var kind: StimulusKind
    public var label: String
    public var desc: String
    public var id: StimulusKind { kind }
}

public struct ModeInfo: Sendable, Identifiable, Hashable {
    public var mode: TherapyMode
    public var title: String
    public var tagline: String
    public var desc: String
    public var level: EvidenceLevel
    public var evidence: String
    public var symbol: String
    public var dose: String
    /// Short citations behind `evidence` (rendered as links in the app).
    public var refs: String = ""
    public var id: TherapyMode { mode }
}

/// Wording follows 08-datenschutz-sicherheit-regulatorik: "Klangprogramme zum Ausprobieren",
/// never "Therapie" as a product claim.
public enum SoundContent {
    public static let stimuli: [StimulusInfo] = [
        StimulusInfo(kind: .nbnThird, label: "Schmalband ⅓ Okt.", desc: "Rauschen eng um deine Tinnitus-Frequenz. Bei Roberts 2008 am wirksamsten, wenn es im Hörverlust-Bereich liegt."),
        StimulusInfo(kind: .nbnOctave, label: "Schmalband 1 Okt.", desc: "Breiteres Band um die Frequenz, meist angenehmer."),
        StimulusInfo(kind: .amTone, label: "AM-Ton 10 Hz", desc: "Ton auf deiner Frequenz, 10× pro Sekunde in der Lautstärke moduliert. Unterdrückt bei manchen stärker als ein reiner Ton."),
        StimulusInfo(kind: .tone, label: "Reiner Ton", desc: "Sinuston genau auf deiner Frequenz."),
        StimulusInfo(kind: .bbn, label: "Breitband", desc: "Weißes Rauschen über alle Frequenzen, der klassische Masker."),
        StimulusInfo(kind: .notchedBbn, label: "Breitband mit Lücke", desc: "Kontrollbedingung: Rauschen mit Lücke um deine Frequenz. Wirkt es genauso, ist der Effekt nicht frequenzspezifisch."),
    ]

    public static func label(_ k: StimulusKind) -> String { stimuli.first { $0.kind == k }?.label ?? k.rawValue }

    public static let modes: [ModeInfo] = [
        ModeInfo(mode: .enrichment, title: "Klanganreicherung", tagline: "Den Kontrast zur Stille nehmen",
                 desc: "Leiser, angenehmer Hintergrundklang knapp unter der Maskierungsschwelle. Neu: personalisiertes, mit 10 Hz moduliertes Rauschen mit Betonung um deine Tinnitus-Frequenz. Läuft im Hintergrund und über Nacht mit Sleep-Timer.",
                 level: .weak,
                 evidence: "Klangtherapie ist Teil der leitliniengerechten Beratung, allein aber schwach belegt. 10-Hz-moduliertes Rauschen senkte in einer nicht-randomisierten Studie (Sendesen 2026, n=71) die Maskierungsschwelle über 6 Monate stärker als unmoduliertes.",
                 symbol: "cloud.rain", dose: "Tag & Nacht", refs: "Mazurek et al. 2022, S3-Leitlinie; Sendesen et al. 2026, Hear Res; Kraft et al. 2025, npj Digit Med"),
        ModeInfo(mode: .reset, title: "Reset-Sitzung", tagline: "Dein bester RI-Klang, im Wechsel mit Stille",
                 desc: "Dein im Labor wirksamster Klang im Wechsel mit Stille. In den Stille-Phasen erlebst du, dass dein Tinnitus veränderbar ist; das allein reduziert bei vielen die Belastung.",
                 level: .experimental,
                 evidence: "Residual Inhibition als Kurzzeiteffekt ist gut belegt (Roberts 2008). Dass Wiederholung dauerhaft wirkt, ist nicht nachgewiesen. Experimentell.",
                 symbol: "waveform", dose: "2× täglich 10–15 min", refs: "Roberts et al. 2008, JARO; Neff et al. 2019; Schoisswohl et al. 2025, JARO"),
        ModeInfo(mode: .notched, title: "Notched Sound", tagline: "Musik oder Rauschen mit Lücke bei deiner Frequenz",
                 desc: "Klang mit einer Lücke um deine Tinnitus-Frequenz, gedacht um über laterale Hemmung die Überaktivität dort zu dämpfen. Funktioniert auch mit deiner eigenen Musik aus der Dateien-App (Apple-Music-Streams sind kopiergeschützt und lassen sich nicht filtern).",
                 level: .weak,
                 evidence: "Frühe Studien positiv (Okamoto 2010). Neuere Meta-Analysen (Alfonso 2024, Tavanai 2024) finden keinen Vorteil gegenüber normaler Musik. Widersprüchlich.",
                 symbol: "music.note", dose: "1–2 h täglich", refs: "Okamoto et al. 2010, PNAS; Alfonso et al. 2024; Tavanai et al. 2024"),
        ModeInfo(mode: .cr, title: "CR-Neuromodulation", tagline: "Vier Töne um deine Frequenz im Zufallstakt",
                 desc: "Vier Töne um deine Tinnitus-Frequenz in zufälliger Folge (Tass 2012). Sollte überaktive Nervenverbände entkoppeln. Sehr leise, nahe der Hörschwelle, wie in der Originalstudie.",
                 level: .experimental,
                 evidence: "Die große doppelblinde RESET2-Studie (Hall 2022, n=100) fand keinen Unterschied zu Placebo. Nur der Vollständigkeit halber enthalten.",
                 symbol: "dot.radiowaves.left.and.right", dose: "flexibel", refs: "Tass et al. 2012; Hall et al. 2022, Brain Sci"),
    ]

    public static func mode(_ m: TherapyMode) -> ModeInfo { modes.first { $0.mode == m }! }

    /// Default level per mode, derived from MML/loudness as in the web app (dBFS).
    public static func defaultLevel(mode: TherapyMode, mmlDb: Double?, loudnessDb: Double) -> Double {
        let mml = mmlDb ?? loudnessDb
        switch mode {
        case .enrichment: return min(-10, mml - 6)
        case .reset: return min(-8, mml + 10)
        case .cr: return min(-14, loudnessDb)
        case .notched: return min(-12, mml)
        }
    }

    public static func defaultMinutes(_ mode: TherapyMode) -> Int {
        switch mode {
        case .reset: 15
        case .enrichment: 30
        default: 60
        }
    }

    public static func defaultSource(_ mode: TherapyMode) -> SoundSource {
        mode == .enrichment ? .am : .pink
    }
}

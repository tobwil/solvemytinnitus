import Foundation

/// Navigation targets shared by the app, widgets, intents and notifications.
public enum AppRoute: Hashable, Sendable, Codable {
    case checkin
    case headphones
    case spectrum
    case match(start: Double?)
    case hearing
    case somatic
    case ri
    case sound(TherapyMode?)
    /// Starts a session right away (widgets, shortcuts): `tinnituslab://sound/enrichment?minutes=30`.
    case play(TherapyMode, minutes: Int)
    case mind
    case lesson(String)
    case tool(String)
    case body(BodyProgramID?)
    case progress(ProgressTab)
    case learn
    case settings

    public enum ProgressTab: String, Codable, Sendable, CaseIterable {
        case overview, journal, weekly
    }

    /// `tinnituslab://` deep links (widgets, intents, notifications).
    public var url: URL {
        var c = URLComponents()
        c.scheme = "tinnituslab"
        switch self {
        case .checkin: c.host = "checkin"
        case .headphones: c.host = "headphones"
        case .spectrum: c.host = "spectrum"
        case .match: c.host = "match"
        case .hearing: c.host = "hearing"
        case .somatic: c.host = "somatic"
        case .ri: c.host = "ri"
        case .sound(let m): c.host = "sound"; if let m { c.path = "/\(m.rawValue)" }
        case .play(let m, let minutes):
            c.host = "sound"
            c.path = "/\(m.rawValue)"
            c.queryItems = [URLQueryItem(name: "minutes", value: "\(minutes)")]
        case .mind: c.host = "mind"
        case .lesson(let id): c.host = "lesson"; c.path = "/\(id)"
        case .tool(let id): c.host = "tool"; c.path = "/\(id)"
        case .body(let p): c.host = "body"; if let p { c.path = "/\(p.rawValue)" }
        case .progress(let t): c.host = "progress"; c.path = "/\(t.rawValue)"
        case .learn: c.host = "learn"
        case .settings: c.host = "settings"
        }
        return c.url!
    }

    public init?(url: URL) {
        guard url.scheme == "tinnituslab", let host = url.host() else { return nil }
        let arg = url.pathComponents.dropFirst().first
        switch host {
        case "checkin": self = .checkin
        case "headphones": self = .headphones
        case "spectrum": self = .spectrum
        case "match": self = .match(start: nil)
        case "hearing": self = .hearing
        case "somatic": self = .somatic
        case "ri": self = .ri
        case "sound", "therapy":
            let mode = arg.flatMap(TherapyMode.init(rawValue:))
            let minutes = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "minutes" }?.value.flatMap(Int.init)
            if let mode, let minutes { self = .play(mode, minutes: minutes) } else { self = .sound(mode) }
        case "mind": self = .mind
        case "lesson": guard let arg else { return nil }; self = .lesson(arg)
        case "tool": guard let arg else { return nil }; self = .tool(arg)
        case "body": self = .body(arg.flatMap(BodyProgramID.init(rawValue:)))
        case "progress": self = .progress(arg.flatMap(ProgressTab.init(rawValue:)) ?? .overview)
        case "learn": self = .learn
        case "settings": self = .settings
        default: return nil
        }
    }
}

public struct LabStep: Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var sub: String
    public var route: AppRoute
    public var done: Bool
    public var meta: String?
}

public struct DayTask: Sendable, Identifiable, Hashable {
    public enum Kind: Sendable, Hashable { case lab, sound, mind, tin, body }
    public var id: String
    public var title: String
    public var sub: String
    public var route: AppRoute
    public var done: Bool
    public var kind: Kind
    public var symbol: String
}

/// Snapshot of everything the program logic needs (built from SwiftData in the app, by hand in tests).
public struct ProgramState: Sendable {
    public var now: Date
    public var programStart: Date?
    public var headphonesOk: Bool
    public var dailyGoalMin: Int
    public var spectrumPeak: Double?
    public var match: (freq: Double, mmlDb: Double?)?
    public var hasHearing: Bool
    public var somatic: Bool?
    public var riTrialCount: Int
    public var checkinTimes: [Date]
    public var sessions: [(date: Date, mode: TherapyMode, durationS: Double)]
    public var mindDates: [Date]
    public var bodyDates: [Date]
    public var journalDays: Set<String>

    public init(now: Date = .now, programStart: Date? = nil, headphonesOk: Bool = false, dailyGoalMin: Int = 60, spectrumPeak: Double? = nil, match: (freq: Double, mmlDb: Double?)? = nil, hasHearing: Bool = false, somatic: Bool? = nil, riTrialCount: Int = 0, checkinTimes: [Date] = [], sessions: [(date: Date, mode: TherapyMode, durationS: Double)] = [], mindDates: [Date] = [], bodyDates: [Date] = [], journalDays: Set<String> = []) {
        self.now = now
        self.programStart = programStart
        self.headphonesOk = headphonesOk
        self.dailyGoalMin = dailyGoalMin
        self.spectrumPeak = spectrumPeak
        self.match = match
        self.hasHearing = hasHearing
        self.somatic = somatic
        self.riTrialCount = riTrialCount
        self.checkinTimes = checkinTimes
        self.sessions = sessions
        self.mindDates = mindDates
        self.bodyDates = bodyDates
        self.journalDays = journalDays
    }
}

public enum Program {
    /// 6 stimuli × 2 repetitions.
    public static let riTarget = 12
    public static let checkinsPerDay = 3
    public static let resetsPerDay = 2

    public static func labSteps(_ s: ProgramState) -> [LabStep] {
        [
            LabStep(id: "phones", title: "Kopfhörer-Check", sub: "Gerät erkennen, links/rechts prüfen, Lautstärke festlegen", route: .headphones, done: s.headphonesOk),
            LabStep(id: "spectrum", title: "Tinnitus-Spektrum", sub: "Ähnlichkeit von 11 Tönen bewerten – robuster als reines Pitch-Matching", route: .spectrum, done: s.spectrumPeak != nil, meta: s.spectrumPeak.map { "Peak \(Format.hz($0))" }),
            LabStep(id: "match", title: "Tonhöhe, Lautheit, Maskierung", sub: "Feinabstimmung auf dem Frequenz-Pad, Oktaven-Check, MML", route: .match(start: s.spectrumPeak), done: s.match != nil, meta: s.match.map { "\(Format.hz($0.freq)) · MML \($0.mmlDb.map { "\(Int($0))" } ?? "–") dB" }),
            LabStep(id: "hearing", title: "Hörcheck", sub: "Apples Hörtest importieren, eigene Messung bis 16 kHz", route: .hearing, done: s.hasHearing),
            LabStep(id: "somatic", title: "Somatik-Check", sub: "Lässt sich dein Tinnitus über Kiefer oder Nacken verändern?", route: .somatic, done: s.somatic != nil, meta: s.somatic.map { $0 ? "somatisch modulierbar" : "nicht modulierbar" }),
            LabStep(id: "ri", title: "Residual-Inhibition-Labor", sub: "6 Stimuli × 2 Durchgänge, verblindet", route: .ri, done: s.riTrialCount >= riTarget, meta: s.riTrialCount > 0 ? "\(min(s.riTrialCount, riTarget))/\(riTarget) Durchgänge" : nil),
        ]
    }

    public static func nextLabStep(_ s: ProgramState) -> LabStep? {
        labSteps(s).first { !$0.done }
    }

    public static func programDay(_ s: ProgramState, calendar: Calendar = .current) -> Int {
        guard let start = s.programStart else { return 1 }
        let d = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: s.now)).day ?? 0
        return max(1, d + 1)
    }

    public static func programWeek(_ s: ProgramState, calendar: Calendar = .current) -> Int {
        max(1, (programDay(s, calendar: calendar) - 1) / 7 + 1)
    }

    public static func weekFocus(_ w: Int) -> String {
        switch w {
        case ...1: "Messwoche: Wir lernen deinen Tinnitus genau kennen."
        case 2...5: "Trainingsphase: Täglich dein wirksamster Klang plus Kopf-Training."
        case 6: "Auswertung: Was wirkt bei dir, was fliegt raus?"
        case 7...8: "Feinschliff: Neu messen und das Protokoll anpassen."
        default: "Erhaltungsphase: Weiter mit dem, was nachweislich wirkt."
        }
    }

    public static func todayTasks(_ s: ProgramState, calendar: Calendar = .current) -> [DayTask] {
        let isToday: (Date) -> Bool = { calendar.isDate($0, inSameDayAs: s.now) }
        let ci = s.checkinTimes.filter(isToday).count
        let today = s.sessions.filter { isToday($0.date) }
        let resets = today.filter { $0.mode == .reset }.count
        let soundMin = Int((today.filter { $0.mode != .reset }.reduce(0) { $0 + $1.durationS } / 60).rounded())
        var tasks: [DayTask] = []

        tasks.append(DayTask(id: "checkin", title: "Kurz-Check-in", sub: "\(min(ci, checkinsPerDay)) von \(checkinsPerDay) heute · morgens, mittags, abends", route: .checkin, done: ci >= checkinsPerDay, kind: .tin, symbol: "waveform.path.ecg"))

        if let lab = nextLabStep(s) {
            tasks.append(DayTask(id: "lab", title: lab.title, sub: "Nächster Mess-Schritt", route: lab.route, done: false, kind: .lab, symbol: "flask"))
        }
        if s.match != nil {
            tasks.append(DayTask(id: "reset", title: "Reset-Sitzung", sub: "\(min(resets, resetsPerDay)) von \(resetsPerDay) · je 10–15 min mit deinem RI-Klang", route: .sound(.reset), done: resets >= resetsPerDay, kind: .sound, symbol: "waveform"))
            tasks.append(DayTask(id: "sound", title: "Klangzeit", sub: "\(soundMin) von \(s.dailyGoalMin) min · Anreicherung oder Notched", route: .sound(nil), done: soundMin >= s.dailyGoalMin, kind: .sound, symbol: "music.note"))
        }
        let mindToday = s.mindDates.contains(where: isToday)
        tasks.append(DayTask(id: "mind", title: "Kopf-Training", sub: "Eine Lektion oder Übung, 5–10 min", route: .mind, done: mindToday, kind: .mind, symbol: "brain.head.profile"))

        if s.somatic == true {
            let bodyToday = s.bodyDates.contains(where: isToday)
            tasks.append(DayTask(id: "body", title: "Körper-Programm", sub: "Nacken oder Kiefer, ca. 8 min · dein Tinnitus ist somatisch modulierbar", route: .body(nil), done: bodyToday, kind: .body, symbol: "figure.cooldown"))
        }

        let journalDone = s.journalDays.contains(Day.key(s.now, calendar: calendar))
        tasks.append(DayTask(id: "journal", title: "Tagesrückblick", sub: "Schlaf, Stress, Auslöser", route: .progress(.journal), done: journalDone, kind: .tin, symbol: "square.and.pencil"))
        return tasks
    }
}

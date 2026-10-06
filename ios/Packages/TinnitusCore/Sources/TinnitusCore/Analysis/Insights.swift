import Foundation

/// Analyses for "Verlauf" (all pure; built from plain values).
public enum Insights {
    public struct DailyValue: Sendable, Hashable, Identifiable {
        public var day: String
        public var date: Date
        public var loudness: Double?
        public var distress: Double?
        public var id: String { day }
    }

    public struct Rating: Sendable {
        public var ts: Date
        public var loudness: Double
        public var distress: Double
        public init(ts: Date, loudness: Double, distress: Double) {
            self.ts = ts
            self.loudness = loudness
            self.distress = distress
        }
    }

    public struct JournalValues: Sendable {
        public var day: String
        public var loudness, distress, sleep, stress: Double
        public var noise, caffeine, alcohol: Bool
        public init(day: String, loudness: Double, distress: Double, sleep: Double, stress: Double, noise: Bool, caffeine: Bool, alcohol: Bool) {
            self.day = day
            self.loudness = loudness
            self.distress = distress
            self.sleep = sleep
            self.stress = stress
            self.noise = noise
            self.caffeine = caffeine
            self.alcohol = alcohol
        }
    }

    /// Daily means of check-ins plus the journal value, oldest first.
    public static func daily(days: Int, checkins: [Rating], journal: [JournalValues], now: Date = .now, calendar: Calendar = .current) -> [DailyValue] {
        var byDay: [String: [Rating]] = [:]
        for c in checkins { byDay[Day.key(c.ts, calendar: calendar), default: []].append(c) }
        let jByDay = Dictionary(journal.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        return (0..<days).reversed().map { i in
            let date = calendar.date(byAdding: .day, value: -i, to: calendar.startOfDay(for: now))!.addingTimeInterval(12 * 3600)
            let k = Day.key(date, calendar: calendar)
            var l = (byDay[k] ?? []).map(\.loudness)
            var d = (byDay[k] ?? []).map(\.distress)
            if let j = jByDay[k] {
                l.append(j.loudness)
                d.append(j.distress)
            }
            return DailyValue(day: k, date: date, loudness: l.isEmpty ? nil : Stats.mean(l), distress: d.isEmpty ? nil : Stats.mean(d))
        }
    }

    public enum Trend: Sendable, Equatable {
        case insufficient, down(Double), up(Double), stable
    }

    /// Second half vs first half of the available values.
    public static func trend(_ values: [Double]) -> Trend {
        guard values.count >= 4 else { return .insufficient }
        let half = values.count / 2
        let delta = Stats.mean(Array(values[half...])) - Stats.mean(Array(values[..<half]))
        if delta <= -0.4 { return .down(delta) }
        if delta >= 0.4 { return .up(delta) }
        return .stable
    }

    // MARK: What works for me

    public struct ModeEffect: Sendable, Identifiable {
        public var mode: TherapyMode
        public var n: Int
        public var interval: Stats.Interval
        /// At least 5 sessions and the whole 95 % interval below 0.
        public var reliable: Bool { n >= 5 && interval.hi < 0 }
        public var id: TherapyMode { mode }
    }

    public static func modeEffects(_ sessions: [(mode: TherapyMode, pre: Double?, post: Double?)]) -> [ModeEffect] {
        TherapyMode.allCases.compactMap { m in
            let deltas = sessions.filter { $0.mode == m }.compactMap { s -> Double? in
                guard let pre = s.pre, let post = s.post else { return nil }
                return post - pre
            }
            guard !deltas.isEmpty else { return nil }
            return ModeEffect(mode: m, n: deltas.count, interval: Stats.ci(deltas))
        }
    }

    /// Days with ≥ 10 min of sound vs days without (observational).
    public static func withVsWithout(daily: [DailyValue], activeDays: Set<String>) -> (with: [Double], without: [Double]) {
        let rated = daily.filter { $0.loudness != nil }
        return (rated.filter { activeDays.contains($0.day) }.map { $0.loudness! },
                rated.filter { !activeDays.contains($0.day) }.map { $0.loudness! })
    }

    // MARK: Time of day

    public struct Slot: Sendable, Identifiable {
        public var label: String
        public var mean: Double?
        public var n: Int
        public var id: String { label }
    }

    public static let slots: [(String, Int, Int)] = [("Nacht", 0, 6), ("Morgen", 6, 11), ("Mittag", 11, 16), ("Abend", 16, 24)]

    public static func timeOfDay(_ checkins: [Rating], calendar: Calendar = .current) -> [Slot] {
        slots.map { label, a, b in
            let v = checkins.filter { let h = calendar.component(.hour, from: $0.ts); return h >= a && h < b }.map(\.loudness)
            return Slot(label: label, mean: v.isEmpty ? nil : Stats.mean(v), n: v.count)
        }
    }

    // MARK: Triggers

    public struct Trigger: Sendable, Identifiable {
        public enum Kind: Sendable { case difference, correlation }
        public var label: String
        public var detail: String
        public var value: Double
        public var kind: Kind
        /// Automatic (from HealthKit) instead of manual input.
        public var automatic: Bool
        public var id: String { label }
        /// Positive = associated with louder tinnitus.
        public var isWarning: Bool { kind == .difference ? value > 0.7 : value > 0.3 }
        public var isGood: Bool { kind == .difference ? value < -0.7 : value < -0.3 }
    }

    public static func flagTrigger(_ label: String, values: [(flag: Bool, loudness: Double)], automatic: Bool = false) -> Trigger? {
        let w = values.filter(\.flag).map(\.loudness)
        let wo = values.filter { !$0.flag }.map(\.loudness)
        guard w.count >= 2, wo.count >= 2 else { return nil }
        return Trigger(label: label, detail: "\(w.count) Tage mit, \(wo.count) ohne", value: Stats.mean(w) - Stats.mean(wo), kind: .difference, automatic: automatic)
    }

    public static func correlationTrigger(_ label: String, xs: [Double], ys: [Double], automatic: Bool = false) -> Trigger? {
        guard xs.count >= 5 else { return nil }
        let r = Stats.pearson(xs, ys)
        return Trigger(label: label, detail: Stats.correlationLabel(r), value: r, kind: .correlation, automatic: automatic)
    }

    public struct HealthDay: Sendable {
        public var day: String
        public var sleepHours: Double?
        public var hrvMs: Double?
        public var loudMinutes: Double?
        public var headphoneDbA: Double?
        public var restingHR: Double?
        public init(day: String, sleepHours: Double? = nil, hrvMs: Double? = nil, loudMinutes: Double? = nil, headphoneDbA: Double? = nil, restingHR: Double? = nil) {
            self.day = day
            self.sleepHours = sleepHours
            self.hrvMs = hrvMs
            self.loudMinutes = loudMinutes
            self.headphoneDbA = headphoneDbA
            self.restingHR = restingHR
        }
    }

    /// Manual triggers from the journal plus automatic ones from HealthKit (noise days, short nights, low HRV).
    public static func triggers(journal: [JournalValues], daily: [DailyValue], health: [HealthDay]) -> [Trigger] {
        var out: [Trigger] = []
        if journal.count >= 7 {
            out += [
                flagTrigger("Koffein", values: journal.map { ($0.caffeine, $0.loudness) }),
                flagTrigger("Alkohol", values: journal.map { ($0.alcohol, $0.loudness) }),
            ].compactMap { $0 }
            if health.allSatisfy({ $0.loudMinutes == nil }) {
                out += [flagTrigger("Lärm", values: journal.map { ($0.noise, $0.loudness) })].compactMap { $0 }
            }
            out += [
                correlationTrigger("Guter Schlaf ↔ Lautheit", xs: journal.map(\.sleep), ys: journal.map(\.loudness)),
                correlationTrigger("Stress ↔ Lautheit", xs: journal.map(\.stress), ys: journal.map(\.loudness)),
            ].compactMap { $0 }
        }
        // automatic triggers: use the day's mean loudness. Noise and headphones act on the *next* day too,
        // so both the same day and the following day are counted.
        let loud = Dictionary(daily.compactMap { d in d.loudness.map { (d.day, $0) } }, uniquingKeysWith: { a, _ in a })
        let healthByDay = Dictionary(health.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        func pairs(_ flag: (HealthDay) -> Bool?) -> [(flag: Bool, loudness: Double)] {
            loud.compactMap { day, l in
                guard let h = healthByDay[day], let f = flag(h) else { return nil }
                return (f, l)
            }
        }
        if let t = flagTrigger("Lärmtag (Watch, > 30 min über 80 dB)", values: pairs { h in h.loudMinutes.map { $0 > 30 } }, automatic: true) { out.append(t) }
        if let t = flagTrigger("Kurze Nacht (< 6 h)", values: pairs { h in h.sleepHours.map { $0 < 6 } }, automatic: true) { out.append(t) }
        let hrvs = health.compactMap(\.hrvMs)
        if hrvs.count >= 5 {
            let median = hrvs.sorted()[hrvs.count / 2]
            if let t = flagTrigger("Niedrige HRV (unter deinem Median)", values: pairs { h in h.hrvMs.map { $0 < median * 0.85 } }, automatic: true) { out.append(t) }
        }
        // Garmin and other wearables write resting heart rate but no HRV to Apple Health
        let rhrs = health.compactMap(\.restingHR)
        if hrvs.count < 5, rhrs.count >= 5 {
            let median = rhrs.sorted()[rhrs.count / 2]
            if let t = flagTrigger("Erhöhter Ruhepuls (über deinem Median + 5)", values: pairs { h in h.restingHR.map { $0 > median + 5 } }, automatic: true) { out.append(t) }
        }
        if let t = flagTrigger("Viel Kopfhörer (> 80 dB(A) Mittel)", values: pairs { h in h.headphoneDbA.map { $0 > 80 } }, automatic: true) { out.append(t) }
        return out
    }

    /// Does the tinnitus get quieter when the neck gets more mobile? (Body module)
    public static func mobilityVsLoudness(rom: [(day: String, total: Double)], daily: [DailyValue]) -> Trigger? {
        let loud = Dictionary(daily.compactMap { d in d.loudness.map { (d.day, $0) } }, uniquingKeysWith: { a, _ in a })
        let pairs = rom.compactMap { r in loud[r.day].map { (r.total, $0) } }
        return correlationTrigger("Beweglichkeit ↔ Lautheit", xs: pairs.map(\.0), ys: pairs.map(\.1), automatic: true)
    }

    // MARK: Weekly

    /// Weekly score has been high (≥ threshold) for the last `weeks` checks → suggest professional help.
    public static func persistentHighDistress(scores: [Int], threshold: Int = SafetyContent.highDistressScore, weeks: Int = 2) -> Bool {
        scores.count >= weeks && scores.suffix(weeks).allSatisfy { $0 >= threshold }
    }
}

// MARK: - Hearing dose

/// Noise dose with a 3 dB exchange rate. WHO safe listening: 80 dB(A) for 40 h per week
/// (≈ 5.7 h per day) is 100 %.
public enum HearingDose {
    public static let referenceDb = 80.0
    public static let referenceHoursPerDay = 40.0 / 7

    /// Fraction of the daily allowance for `seconds` at `db` SPL.
    public static func fraction(db: Double, seconds: Double) -> Double {
        let allowedS = referenceHoursPerDay * 3600 / pow(2, (db - referenceDb) / 3)
        return seconds / allowedS
    }
}

// MARK: - Calibration plausibility

/// Cross-check of the app's level estimate against HealthKit's headphone exposure (Apple headphones):
/// the median difference over sessions, clamped to ±3 dB (05-audio-engine, step 3).
public enum Plausibility {
    public static let maxCorrection = 3.0
    public static let minSessions = 3

    /// - Parameter pairs: (HealthKit LEQ, own estimate) per session.
    public static func correction(_ pairs: [(healthKit: Double, estimate: Double)]) -> Double? {
        guard pairs.count >= minSessions else { return nil }
        let diffs = pairs.map { $0.healthKit - $0.estimate }.sorted()
        let m = diffs.count % 2 == 1 ? diffs[diffs.count / 2] : (diffs[diffs.count / 2 - 1] + diffs[diffs.count / 2]) / 2
        return min(maxCorrection, max(-maxCorrection, m))
    }

    /// Key in `AppSettings.calibrationOffsets` for the plausibility part.
    public static func key(_ kind: DeviceKind) -> String { "plaus.\(kind.rawValue)" }

    /// Anchor offset plus plausibility correction per device kind.
    public static func combinedOffsets(_ offsets: [String: Double]) -> [String: Double] {
        var out: [String: Double] = [:]
        for kind in DeviceKind.allCases {
            let v = (offsets[kind.rawValue] ?? 0) + (offsets[key(kind)] ?? 0)
            if v != 0 { out[kind.rawValue] = v }
        }
        return out
    }
}

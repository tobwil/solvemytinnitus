import Foundation
import SwiftData

/// JSON format of the web app (`AppData`, version 1 and 2). iOS-only data travels in the optional
/// `ios` key, which the web app keeps untouched on import.
public struct WebAppData: Codable, Sendable {
    public var version: Int
    public var settings: Settings?
    public var hearingTests: [Hearing]?
    public var spectra: [Spectrum]?
    public var matches: [Match]?
    public var riTrials: [RI]?
    public var somatic: [Somatic]?
    public var sessions: [Session]?
    public var checkins: [Check]?
    public var journal: [Journal]?
    public var weekly: [Weekly]?
    public var mind: Mind?
    public var ios: IOSExtras?

    public struct Settings: Codable, Sendable {
        public var masterVolume: Double?
        public var preferredEar: Ear?
        public var notchWidthOctaves: Double?
        public var dailyGoalMin: Int?
        public var name: String?
        public var onboarded: Bool?
        public var headphonesOk: Bool?
        public var programStart: String?
        public var blindRi: Bool?

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(masterVolume, forKey: .masterVolume); try c.encodeIfPresent(preferredEar, forKey: .preferredEar)
            try c.encodeIfPresent(notchWidthOctaves, forKey: .notchWidthOctaves); try c.encodeIfPresent(dailyGoalMin, forKey: .dailyGoalMin)
            try c.encodeIfPresent(name, forKey: .name); try c.encodeIfPresent(onboarded, forKey: .onboarded)
            try c.encodeIfPresent(headphonesOk, forKey: .headphonesOk); try c.encode(programStart, forKey: .programStart)
            try c.encodeIfPresent(blindRi, forKey: .blindRi)
        }
    }

    public struct Hearing: Codable, Sendable { public var id: String; public var date: String; public var left: [HearingPoint]; public var right: [HearingPoint] }
    public struct Spectrum: Codable, Sendable { public var id: String; public var date: String; public var ear: Ear; public var timbre: Timbre; public var points: [SpectrumPoint]; public var peak: Double }
    public struct Match: Codable, Sendable {
        public var id: String; public var date: String; public var ear: Ear; public var freq: Double; public var trials: [Double]
        public var spreadOctaves: Double; public var loudnessDb: Double; public var timbre: Timbre; public var mmlDb: Double?

        // the web app checks `mmlDb === null`, so nil must be encoded as an explicit null
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id); try c.encode(date, forKey: .date); try c.encode(ear, forKey: .ear)
            try c.encode(freq, forKey: .freq); try c.encode(trials, forKey: .trials); try c.encode(spreadOctaves, forKey: .spreadOctaves)
            try c.encode(loudnessDb, forKey: .loudnessDb); try c.encode(timbre, forKey: .timbre); try c.encode(mmlDb, forKey: .mmlDb)
        }
    }
    public struct RI: Codable, Sendable {
        public var id: String; public var date: String; public var stimulus: StimulusKind; public var blind: Bool?
        public var centerFreq: Double; public var levelDb: Double; public var durationS: Double; public var curve: [Double]
        public var baseline: Double; public var depth: Double; public var durationOfEffectS: Double
    }
    public struct Somatic: Codable, Sendable { public var id: String; public var date: String; public var results: [SomaticResult]; public var somatic: Bool }
    public struct Session: Codable, Sendable {
        public var id: String; public var date: String; public var mode: String; public var durationS: Double
        public var pre: Double?; public var post: Double?; public var params: [String: JSONScalar]?

        // the web app filters with `pre !== null`, so nil must be an explicit null
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id); try c.encode(date, forKey: .date); try c.encode(mode, forKey: .mode)
            try c.encode(durationS, forKey: .durationS); try c.encode(pre, forKey: .pre); try c.encode(post, forKey: .post)
            try c.encode(params ?? [:], forKey: .params)
        }
    }
    public struct Check: Codable, Sendable { public var id: String; public var ts: String; public var loudness: Double; public var distress: Double }
    public struct Journal: Codable, Sendable {
        public var id: String; public var date: String; public var loudness: Double; public var distress: Double; public var sleep: Double; public var stress: Double
        public var noiseExposure: Bool; public var caffeine: Bool; public var alcohol: Bool; public var notes: String
    }
    public struct Weekly: Codable, Sendable { public var id: String; public var date: String; public var answers: [Int]; public var score: Int }
    public struct Thought: Codable, Sendable {
        public var id: String; public var date: String; public var situation: String; public var thought: String
        public var feeling: Double; public var alternative: String; public var feelingAfter: Double
    }
    public struct Exercise: Codable, Sendable { public var id: String; public var date: String; public var kind: String; public var durationS: Double }
    public struct Mind: Codable, Sendable {
        public var lessonsDone: [String]?
        public var exercises: [Exercise]?
        public var thoughts: [Thought]?
        public var spikePlan: String?
    }

    public struct IOSExtras: Codable, Sendable {
        public var bodySessions: [Body]?
        public var health: [Health]?
        public var contraindications: [String]?
        public struct Body: Codable, Sendable {
            public var id: String; public var date: String; public var program: BodyProgramID; public var durationS: Double
            public var completedExercises: Int; public var gentleOnly: Bool; public var rom: NeckROM?; public var jawTension: Double?
        }
        public struct Health: Codable, Sendable {
            public var day: String; public var sleepHours: Double?; public var hrvMs: Double?; public var restingHR: Double?
            public var loudMinutes: Double?; public var headphoneDbA: Double?; public var headphoneMinutes: Double?
        }
    }
}

/// number | string | bool, for the web app's untyped session params.
public enum JSONScalar: Codable, Sendable, Hashable {
    case number(Double), string(String), bool(Bool)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else { self = .string(try c.decode(String.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .number(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .bool(let b): try c.encode(b)
        }
    }

    var double: Double? { if case .number(let d) = self { d } else { nil } }
    var string: String? { if case .string(let s) = self { s } else { nil } }
}

public enum ISODate {
    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()

    public static func parse(_ s: String) -> Date? {
        withFraction.date(from: s) ?? plain.date(from: s) ?? Day.date(fromKey: s)
    }

    public static func string(_ d: Date) -> String { withFraction.string(from: d) }
}

public enum ImportError: LocalizedError {
    case unknownFormat
    public var errorDescription: String? { "Unbekanntes Datenformat" }
}

public enum DataTransfer {
    public static func decode(_ data: Data) throws -> WebAppData {
        let parsed = try JSONDecoder().decode(WebAppData.self, from: data)
        guard parsed.version == 1 || parsed.version == 2 else { throw ImportError.unknownFormat }
        return parsed
    }

    /// Inserts all records. Replaces existing data when `replace` is true (default, like the web app).
    @MainActor
    public static func importData(_ data: Data, into ctx: ModelContext, replace: Bool = true) throws {
        let d = try decode(data)
        if replace { try ctx.deleteEverything() }
        let date: (String) -> Date = { ISODate.parse($0) ?? .now }

        let s = ctx.settings()
        if let w = d.settings {
            s.masterVolume = w.masterVolume ?? s.masterVolume
            s.preferredEar = w.preferredEar ?? s.preferredEar
            s.notchWidthOctaves = w.notchWidthOctaves ?? s.notchWidthOctaves
            s.dailyGoalMin = w.dailyGoalMin ?? s.dailyGoalMin
            s.name = w.name ?? s.name
            s.onboarded = w.onboarded ?? s.onboarded
            s.headphonesOk = w.headphonesOk ?? s.headphonesOk
            s.programStart = w.programStart.flatMap(ISODate.parse) ?? s.programStart
            s.blindRi = w.blindRi ?? s.blindRi
        }
        if let m = d.mind {
            s.lessonsDone = m.lessonsDone ?? []
            s.spikePlan = m.spikePlan ?? ""
        }
        // users who already measured something on v1 don't need onboarding again
        if d.version == 1, !(d.matches ?? []).isEmpty || !(d.journal ?? []).isEmpty { s.onboarded = true }
        s.contraindications = d.ios?.contraindications ?? s.contraindications

        for h in d.hearingTests ?? [] { ctx.insert(HearingTest(uid: h.id, date: date(h.date), left: h.left, right: h.right)) }
        for x in d.spectra ?? [] { ctx.insert(TinnitusSpectrum(uid: x.id, date: date(x.date), ear: x.ear, timbre: x.timbre, points: x.points, peak: x.peak)) }
        for m in d.matches ?? [] {
            ctx.insert(TinnitusMatch(uid: m.id, date: date(m.date), ear: m.ear, freq: m.freq, trials: m.trials, spreadOctaves: m.spreadOctaves, loudnessDb: m.loudnessDb, timbre: m.timbre, mmlDb: m.mmlDb))
        }
        for t in d.riTrials ?? [] {
            ctx.insert(RITrial(uid: t.id, date: date(t.date), stimulus: t.stimulus, blind: t.blind ?? false, centerFreq: t.centerFreq, levelDb: t.levelDb, durationS: t.durationS, curve: t.curve, baseline: t.baseline, depth: t.depth, durationOfEffectS: t.durationOfEffectS))
        }
        for x in d.somatic ?? [] { ctx.insert(SomaticTest(uid: x.id, date: date(x.date), results: x.results, somatic: x.somatic)) }
        // v1 had a 'bimodal' therapy mode that was removed
        for x in d.sessions ?? [] {
            guard let mode = TherapyMode(rawValue: x.mode) else { continue }
            let p = x.params ?? [:]
            let params = SessionParams(
                levelDb: p["level"]?.double ?? -30,
                source: p["source"]?.string.flatMap(SoundSource.init(rawValue:)),
                stimulus: p["stimulus"]?.string.flatMap(StimulusKind.init(rawValue:)),
                notchWidthOctaves: p["width"]?.double,
                origin: p["origin"]?.string.flatMap(EntryOrigin.init(rawValue:))
            )
            ctx.insert(TherapySession(uid: x.id, date: date(x.date), mode: mode, durationS: x.durationS, pre: x.pre, post: x.post, params: params))
        }
        for c in d.checkins ?? [] { ctx.insert(CheckIn(uid: c.id, ts: date(c.ts), loudness: c.loudness, distress: c.distress)) }
        for j in d.journal ?? [] {
            ctx.insert(JournalEntry(uid: j.id, day: j.date, loudness: j.loudness, distress: j.distress, sleep: j.sleep, stress: j.stress, noiseExposure: j.noiseExposure, caffeine: j.caffeine, alcohol: j.alcohol, notes: j.notes))
        }
        for w in d.weekly ?? [] { ctx.insert(WeeklyCheck(uid: w.id, date: date(w.date), answers: w.answers, score: w.score)) }
        for t in d.mind?.thoughts ?? [] {
            ctx.insert(ThoughtRecord(uid: t.id, date: date(t.date), situation: t.situation, thought: t.thought, feeling: t.feeling, alternative: t.alternative, feelingAfter: t.feelingAfter))
        }
        for e in d.mind?.exercises ?? [] { ctx.insert(MindExercise(uid: e.id, date: date(e.date), kind: e.kind, durationS: e.durationS)) }
        for b in d.ios?.bodySessions ?? [] {
            ctx.insert(BodySession(uid: b.id, date: date(b.date), program: b.program, durationS: b.durationS, completedExercises: b.completedExercises, gentleOnly: b.gentleOnly, rom: b.rom, jawTension: b.jawTension))
        }
        for h in d.ios?.health ?? [] {
            let snap = HealthSnapshot(day: h.day)
            snap.sleepHours = h.sleepHours
            snap.hrvMs = h.hrvMs
            snap.restingHR = h.restingHR
            snap.loudMinutes = h.loudMinutes
            snap.headphoneDbA = h.headphoneDbA
            snap.headphoneMinutes = h.headphoneMinutes
            ctx.insert(snap)
        }
        try ctx.save()
    }

    /// Export everything as web-compatible JSON (version 2).
    @MainActor
    public static func exportData(from ctx: ModelContext) throws -> Data {
        let s = ctx.settings()
        let iso = ISODate.string
        let byDate = { (a: Date, b: Date) in a < b }
        let d = WebAppData(
            version: 2,
            settings: .init(masterVolume: s.masterVolume, preferredEar: s.preferredEar, notchWidthOctaves: s.notchWidthOctaves, dailyGoalMin: s.dailyGoalMin, name: s.name, onboarded: s.onboarded, headphonesOk: s.headphonesOk, programStart: s.programStart.map(iso), blindRi: s.blindRi),
            hearingTests: ctx.all(HearingTest.self).sorted { byDate($0.date, $1.date) }.map { .init(id: $0.uid, date: iso($0.date), left: $0.left, right: $0.right) },
            spectra: ctx.all(TinnitusSpectrum.self).sorted { byDate($0.date, $1.date) }.map { .init(id: $0.uid, date: iso($0.date), ear: $0.ear, timbre: $0.timbre, points: $0.points, peak: $0.peak) },
            matches: ctx.all(TinnitusMatch.self).sorted { byDate($0.date, $1.date) }.map { .init(id: $0.uid, date: iso($0.date), ear: $0.ear, freq: $0.freq, trials: $0.trials, spreadOctaves: $0.spreadOctaves, loudnessDb: $0.loudnessDb, timbre: $0.timbre, mmlDb: $0.mmlDb) },
            riTrials: ctx.all(RITrial.self).sorted { byDate($0.date, $1.date) }.map { .init(id: $0.uid, date: iso($0.date), stimulus: $0.stimulus, blind: $0.blind, centerFreq: $0.centerFreq, levelDb: $0.levelDb, durationS: $0.durationS, curve: $0.curve, baseline: $0.baseline, depth: $0.depth, durationOfEffectS: $0.durationOfEffectS) },
            somatic: ctx.all(SomaticTest.self).sorted { byDate($0.date, $1.date) }.map { .init(id: $0.uid, date: iso($0.date), results: $0.results, somatic: $0.somatic) },
            sessions: ctx.all(TherapySession.self).sorted { byDate($0.date, $1.date) }.map { x in
                var p: [String: JSONScalar] = ["level": .number(x.params.levelDb)]
                if let v = x.params.source { p["source"] = .string(v.rawValue) }
                if let v = x.params.stimulus { p["stimulus"] = .string(v.rawValue) }
                if let v = x.params.notchWidthOctaves { p["width"] = .number(v) }
                if let v = x.params.origin { p["origin"] = .string(v.rawValue) }
                return .init(id: x.uid, date: iso(x.date), mode: x.mode.rawValue, durationS: x.durationS, pre: x.pre, post: x.post, params: p)
            },
            checkins: ctx.all(CheckIn.self).sorted { byDate($0.ts, $1.ts) }.map { .init(id: $0.uid, ts: iso($0.ts), loudness: $0.loudness, distress: $0.distress) },
            journal: ctx.all(JournalEntry.self).sorted { $0.day < $1.day }.map { .init(id: $0.uid, date: $0.day, loudness: $0.loudness, distress: $0.distress, sleep: $0.sleep, stress: $0.stress, noiseExposure: $0.noiseExposure, caffeine: $0.caffeine, alcohol: $0.alcohol, notes: $0.notes) },
            weekly: ctx.all(WeeklyCheck.self).sorted { byDate($0.date, $1.date) }.map { .init(id: $0.uid, date: iso($0.date), answers: $0.answers, score: $0.score) },
            mind: .init(
                lessonsDone: s.lessonsDone,
                exercises: ctx.all(MindExercise.self).sorted { byDate($0.date, $1.date) }.map { .init(id: $0.uid, date: iso($0.date), kind: $0.kind, durationS: $0.durationS) },
                thoughts: ctx.all(ThoughtRecord.self).sorted { byDate($0.date, $1.date) }.map { .init(id: $0.uid, date: iso($0.date), situation: $0.situation, thought: $0.thought, feeling: $0.feeling, alternative: $0.alternative, feelingAfter: $0.feelingAfter) },
                spikePlan: s.spikePlan
            ),
            ios: .init(
                bodySessions: ctx.all(BodySession.self).sorted { byDate($0.date, $1.date) }.map { .init(id: $0.uid, date: iso($0.date), program: $0.program, durationS: $0.durationS, completedExercises: $0.completedExercises, gentleOnly: $0.gentleOnly, rom: $0.rom, jawTension: $0.jawTension) },
                health: ctx.all(HealthSnapshot.self).sorted { $0.day < $1.day }.map { .init(day: $0.day, sleepHours: $0.sleepHours, hrvMs: $0.hrvMs, restingHR: $0.restingHR, loudMinutes: $0.loudMinutes, headphoneDbA: $0.headphoneDbA, headphoneMinutes: $0.headphoneMinutes) },
                contraindications: s.contraindications
            )
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(d)
    }
}

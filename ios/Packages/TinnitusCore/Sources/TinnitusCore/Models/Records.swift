import Foundation
import SwiftData

// SwiftData records. CloudKit-compatible: every attribute has a default, no unique constraints,
// no required relationships. The device is embedded as a value instead of a relationship so that
// records sync independently.

@Model
public final class HearingTest {
    public var uid: String = UUID().uuidString
    public var date: Date = Date.now
    public var left: [HearingPoint] = []
    public var right: [HearingPoint] = []
    public var source: HearingSource = HearingSource.app
    public var device: DeviceStamp = DeviceStamp.unknown

    public init(uid: String = UUID().uuidString, date: Date = .now, left: [HearingPoint], right: [HearingPoint], source: HearingSource = .app, device: DeviceStamp = .unknown) {
        self.uid = uid
        self.date = date
        self.left = left
        self.right = right
        self.source = source
        self.device = device
    }
}

/// Likeness-rating tinnitus spectrum (Noreña et al. 2002).
@Model
public final class TinnitusSpectrum {
    public var uid: String = UUID().uuidString
    public var date: Date = Date.now
    public var ear: Ear = Ear.both
    public var timbre: Timbre = Timbre.tone
    public var points: [SpectrumPoint] = []
    public var peak: Double = 6000
    public var device: DeviceStamp = DeviceStamp.unknown

    public init(uid: String = UUID().uuidString, date: Date = .now, ear: Ear, timbre: Timbre, points: [SpectrumPoint], peak: Double, device: DeviceStamp = .unknown) {
        self.uid = uid
        self.date = date
        self.ear = ear
        self.timbre = timbre
        self.points = points
        self.peak = peak
        self.device = device
    }
}

@Model
public final class TinnitusMatch {
    public var uid: String = UUID().uuidString
    public var date: Date = Date.now
    public var ear: Ear = Ear.both
    public var freq: Double = 6000
    public var trials: [Double] = []
    public var spreadOctaves: Double = 0
    public var loudnessDb: Double = -32
    public var timbre: Timbre = Timbre.tone
    public var mmlDb: Double?
    public var device: DeviceStamp = DeviceStamp.unknown

    public init(uid: String = UUID().uuidString, date: Date = .now, ear: Ear, freq: Double, trials: [Double], spreadOctaves: Double, loudnessDb: Double, timbre: Timbre, mmlDb: Double?, device: DeviceStamp = .unknown) {
        self.uid = uid
        self.date = date
        self.ear = ear
        self.freq = freq
        self.trials = trials
        self.spreadOctaves = spreadOctaves
        self.loudnessDb = loudnessDb
        self.timbre = timbre
        self.mmlDb = mmlDb
        self.device = device
    }
}

@Model
public final class RITrial {
    public var uid: String = UUID().uuidString
    public var date: Date = Date.now
    public var stimulus: StimulusKind = StimulusKind.nbnThird
    public var blind: Bool = true
    public var centerFreq: Double = 6000
    public var levelDb: Double = -30
    public var durationS: Double = 60
    /// Loudness ratings (0–10) sampled every 2 s after stimulus offset.
    public var curve: [Double] = []
    public var baseline: Double = 5
    public var depth: Double = 0
    public var durationOfEffectS: Double = 0
    public var device: DeviceStamp = DeviceStamp.unknown

    public init(uid: String = UUID().uuidString, date: Date = .now, stimulus: StimulusKind, blind: Bool, centerFreq: Double, levelDb: Double, durationS: Double, curve: [Double], baseline: Double, depth: Double, durationOfEffectS: Double, device: DeviceStamp = .unknown) {
        self.uid = uid
        self.date = date
        self.stimulus = stimulus
        self.blind = blind
        self.centerFreq = centerFreq
        self.levelDb = levelDb
        self.durationS = durationS
        self.curve = curve
        self.baseline = baseline
        self.depth = depth
        self.durationOfEffectS = durationOfEffectS
        self.device = device
    }
}

@Model
public final class SomaticTest {
    public var uid: String = UUID().uuidString
    public var date: Date = Date.now
    public var results: [SomaticResult] = []
    public var somatic: Bool = false
    /// Optional neck mobility baseline from head tracking.
    public var rom: NeckROM?

    public init(uid: String = UUID().uuidString, date: Date = .now, results: [SomaticResult], somatic: Bool, rom: NeckROM? = nil) {
        self.uid = uid
        self.date = date
        self.results = results
        self.somatic = somatic
        self.rom = rom
    }
}

@Model
public final class TherapySession {
    public var uid: String = UUID().uuidString
    public var date: Date = Date.now
    public var mode: TherapyMode = TherapyMode.enrichment
    public var durationS: Double = 0
    public var pre: Double?
    public var post: Double?
    public var params: SessionParams = SessionParams(levelDb: -30)

    public init(uid: String = UUID().uuidString, date: Date = .now, mode: TherapyMode, durationS: Double, pre: Double?, post: Double?, params: SessionParams) {
        self.uid = uid
        self.date = date
        self.mode = mode
        self.durationS = durationS
        self.pre = pre
        self.post = post
        self.params = params
    }
}

/// Ecological momentary assessment: quick in-the-moment rating.
@Model
public final class CheckIn {
    public var uid: String = UUID().uuidString
    public var ts: Date = Date.now
    public var loudness: Double = 0
    public var distress: Double = 0
    public var origin: EntryOrigin = EntryOrigin.app

    public init(uid: String = UUID().uuidString, ts: Date = .now, loudness: Double, distress: Double, origin: EntryOrigin = .app) {
        self.uid = uid
        self.ts = ts
        self.loudness = loudness
        self.distress = distress
        self.origin = origin
    }
}

@Model
public final class JournalEntry {
    public var uid: String = UUID().uuidString
    /// YYYY-MM-DD in the user's calendar.
    public var day: String = ""
    public var loudness: Double = 5
    public var distress: Double = 5
    public var sleep: Double = 5
    public var stress: Double = 5
    public var noiseExposure: Bool = false
    public var caffeine: Bool = false
    public var alcohol: Bool = false
    /// Red flags noted that day (sudden change, one-sided, pulsatile, hearing loss, vertigo).
    public var redFlag: Bool = false
    public var notes: String = ""

    public init(uid: String = UUID().uuidString, day: String, loudness: Double = 5, distress: Double = 5, sleep: Double = 5, stress: Double = 5, noiseExposure: Bool = false, caffeine: Bool = false, alcohol: Bool = false, redFlag: Bool = false, notes: String = "") {
        self.uid = uid
        self.day = day
        self.loudness = loudness
        self.distress = distress
        self.sleep = sleep
        self.stress = stress
        self.noiseExposure = noiseExposure
        self.caffeine = caffeine
        self.alcohol = alcohol
        self.redFlag = redFlag
        self.notes = notes
    }
}

@Model
public final class WeeklyCheck {
    public var uid: String = UUID().uuidString
    public var date: Date = Date.now
    public var answers: [Int] = []
    public var score: Int = 0

    public init(uid: String = UUID().uuidString, date: Date = .now, answers: [Int], score: Int) {
        self.uid = uid
        self.date = date
        self.answers = answers
        self.score = score
    }
}

@Model
public final class ThoughtRecord {
    public var uid: String = UUID().uuidString
    public var date: Date = Date.now
    public var situation: String = ""
    public var thought: String = ""
    public var feeling: Double = 0
    public var alternative: String = ""
    public var feelingAfter: Double = 0

    public init(uid: String = UUID().uuidString, date: Date = .now, situation: String, thought: String, feeling: Double, alternative: String, feelingAfter: Double) {
        self.uid = uid
        self.date = date
        self.situation = situation
        self.thought = thought
        self.feeling = feeling
        self.alternative = alternative
        self.feelingAfter = feelingAfter
    }
}

/// Lessons, guided exercises, thought checks, plan edits. `kind` is e.g. "breath", "lesson:l3".
@Model
public final class MindExercise {
    public var uid: String = UUID().uuidString
    public var date: Date = Date.now
    public var kind: String = ""
    public var durationS: Double = 0
    public var origin: EntryOrigin = EntryOrigin.app

    public init(uid: String = UUID().uuidString, date: Date = .now, kind: String, durationS: Double, origin: EntryOrigin = .app) {
        self.uid = uid
        self.date = date
        self.kind = kind
        self.durationS = durationS
        self.origin = origin
    }
}

public enum BodyProgramID: String, Codable, Sendable, CaseIterable, Identifiable {
    case neck, jaw
    public var id: String { rawValue }
}

@Model
public final class BodySession {
    public var uid: String = UUID().uuidString
    public var date: Date = Date.now
    public var program: BodyProgramID = BodyProgramID.neck
    public var durationS: Double = 0
    public var completedExercises: Int = 0
    public var gentleOnly: Bool = false
    public var rom: NeckROM?
    /// Self-rated jaw tension 0–10 after the session (jaw program).
    public var jawTension: Double?

    public init(uid: String = UUID().uuidString, date: Date = .now, program: BodyProgramID, durationS: Double, completedExercises: Int, gentleOnly: Bool, rom: NeckROM? = nil, jawTension: Double? = nil) {
        self.uid = uid
        self.date = date
        self.program = program
        self.durationS = durationS
        self.completedExercises = completedExercises
        self.gentleOnly = gentleOnly
        self.rom = rom
        self.jawTension = jawTension
    }
}

/// Daily values derived from HealthKit, cached so analyses work offline and across devices.
@Model
public final class HealthSnapshot {
    public var day: String = ""
    public var sleepHours: Double?
    public var hrvMs: Double?
    public var restingHR: Double?
    public var respiratoryRate: Double?
    /// Minutes with environmental noise above 80 dB(A) (Apple Watch).
    public var loudMinutes: Double?
    /// Headphone exposure, energy-averaged dB(A) over the listening time.
    public var headphoneDbA: Double?
    public var headphoneMinutes: Double?
    public var updatedAt: Date = Date.now

    public init(day: String) {
        self.day = day
    }
}

/// Single settings record (fetch-or-create).
@Model
public final class AppSettings {
    public var masterVolume: Double = 0.5
    public var preferredEar: Ear = Ear.both
    public var notchWidthOctaves: Double = 1
    public var dailyGoalMin: Int = 60
    public var name: String = ""
    public var onboarded: Bool = false
    public var headphonesOk: Bool = false
    public var programStart: Date?
    public var blindRi: Bool = true
    public var spikePlan: String = ""
    public var lessonsDone: [String] = []
    /// Body module contraindications answered (nil = not asked yet).
    public var contraindications: [String]?
    /// Check-in reminders at random times within morning/noon/evening windows.
    public var remindersOn: Bool = false
    public var reminderWindows: [Int] = [0, 1, 2]
    public var sessionRemindersOn: Bool = false
    /// Daily 9:00 reminder for a lesson or exercise.
    public var lessonReminderOn: Bool = false
    /// Gentle hint during sound sessions when the head stays tilted forward (AirPods).
    public var postureHint: Bool = false
    public var useHealthKit: Bool = false
    public var mixWithOthers: Bool = false
    public var speakTTS: Bool = false
    /// Personal level offset per device kind from the 1 kHz threshold anchor (dB).
    public var calibrationOffsets: [String: Double] = [:]

    public init() {}

    public var bodyGentleOnly: Bool { !(contraindications ?? []).isEmpty }
}

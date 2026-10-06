import Foundation
import SwiftData
import Testing
@testable import TinnitusCore

@Suite("Program & analysis")
struct LogicTests {
    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }

    @Test func programWeekAndDay() {
        let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 9))!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 20))!
        let s = ProgramState(now: now, programStart: start)
        #expect(Program.programDay(s, calendar: cal) == 15)
        #expect(Program.programWeek(s, calendar: cal) == 3)
        #expect(Program.programWeek(ProgramState(now: start, programStart: start), calendar: cal) == 1)
    }

    @Test func tasksBeforeMeasurement() {
        let s = ProgramState(now: .now)
        let ids = Program.todayTasks(s, calendar: cal).map(\.id)
        #expect(ids == ["checkin", "lab", "mind", "journal"])
        #expect(Program.nextLabStep(s)?.id == "phones")
    }

    @Test func tasksAfterMeasurementAndAutoCompletion() {
        let now = Date.now
        var s = ProgramState(now: now, headphonesOk: true, dailyGoalMin: 30, spectrumPeak: 6000, match: (6000, -40), hasHearing: true, somatic: true, riTrialCount: 12)
        s.checkinTimes = [now, now, now.addingTimeInterval(-60)]
        s.sessions = [(now, .reset, 600), (now, .reset, 600), (now, .enrichment, 1800)]
        s.bodyDates = [now]
        let tasks = Program.todayTasks(s, calendar: cal)
        #expect(tasks.map(\.id) == ["checkin", "reset", "sound", "mind", "body", "journal"])
        #expect(tasks.first { $0.id == "checkin" }?.done == true)
        #expect(tasks.first { $0.id == "reset" }?.done == true)
        #expect(tasks.first { $0.id == "sound" }?.done == true)
        #expect(tasks.first { $0.id == "body" }?.done == true)
        #expect(tasks.first { $0.id == "mind" }?.done == false)
    }

    @Test func riEvaluateAndRank() {
        let e = RIAnalysis.evaluate(baseline: 6, curve: [3, 3, 4, 5, 5.5, 6])
        #expect(e.depth == 3)
        #expect(e.durationS == 8) // first value ≥ 5.4 at index 4
        #expect(RIAnalysis.evaluate(baseline: 5, curve: [5, 6]).depth == 0)
        let trials: [RIAnalysis.TrialValues] = [
            .init(stimulus: .nbnThird, depth: 3, durationOfEffectS: 30),
            .init(stimulus: .nbnThird, depth: 2, durationOfEffectS: 20),
            .init(stimulus: .bbn, depth: 1, durationOfEffectS: 60),
            .init(stimulus: .tone, depth: 0, durationOfEffectS: 0),
        ]
        let sum = RIAnalysis.summarize(trials)
        #expect(sum.first?.stimulus == .nbnThird)
        #expect(abs(sum.first!.score - 2.5 * (1 + 25.0 / 60)) < 1e-9)
        #expect(RIAnalysis.best([.init(stimulus: .tone, depth: 0, durationOfEffectS: 0)]) == nil)
        var g = FastRandom(seed: 7)
        let next = RIAnalysis.leastTested([.nbnThird, .bbn, .tone, .amTone, .nbnOctave], using: &g)
        #expect(next == .notchedBbn)
        #expect(RIAnalysis.suggestedLevel(mmlDb: -40, loudnessDb: -30) == -30)
        #expect(RIAnalysis.suggestedLevel(mmlDb: -12, loudnessDb: -30) == -8)
    }

    @Test func spectrumEvaluate() {
        var r: [Double: [Double]] = [:]
        for f in SpectrumAnalysis.frequencies { r[f] = [1, 1] }
        r[8000] = [9, 8]
        r[10000] = [6, 6]
        let res = SpectrumAnalysis.evaluate(r)
        #expect(res.peak == 8000)
        #expect(res.shapeLabel == "tonal, schmalbandig")
        #expect(abs(res.consistency - 1.0 / 11) < 1e-9)
    }

    @Test func matchCombine() {
        let c = MatchAnalysis.combine(trials: [6000, 6200, 5800])
        #expect(abs(c.freq - 6000) < 1)
        #expect(c.spreadOctaves < 0.06)
        #expect(MatchAnalysis.octaveCandidates(12000) == [6000, 12000])
        #expect(abs(MatchAnalysis.freq(at: MatchAnalysis.position(of: 7000)) - 7000) < 1e-6)
    }

    @Test("Staircase finds a simulated threshold within 5 dB")
    func staircase() {
        let thresholds: [Double: Double] = [500: -70, 1000: -72, 2000: -68, 3000: -65, 4000: -60, 6000: -50, 8000: -45, 10000: -40, 12000: -30, 14000: -20, 16000: -6]
        var s = HearingStaircase()
        var guardCount = 0
        while !s.isDone && guardCount < 500 {
            let f = s.currentFrequency!
            s.answer(heard: s.level >= thresholds[f]!)
            guardCount += 1
        }
        #expect(s.isDone)
        for p in s.results {
            #expect(abs(p.level - thresholds[p.freq]!) <= 5, "\(p.freq): \(p.level)")
        }
        let drop = HearingAnalysis.highFrequencyDrop(s.results)!
        #expect(drop > 20)
    }

    @Test func lossEdgeAndInaudible() {
        let pts = [HearingPoint(freq: 2000, level: -70), HearingPoint(freq: 4000, level: -66), HearingPoint(freq: 6000, level: -40),
                   HearingPoint(freq: 8000, level: -30), HearingPoint(freq: 12000, level: -6)]
        let edge = HearingAnalysis.lossEdge(pts)!
        #expect(edge > 4000 && edge < 6000)
        #expect(HearingAnalysis.notHeard(pts) == [12000])
        #expect(HearingAnalysis.edgeHint(edge: edge, tinnitus: 6000).contains("genau an dieser Kante"))
        #expect(HearingAnalysis.lossEdge([HearingPoint(freq: 1000, level: -60), HearingPoint(freq: 2000, level: -61), HearingPoint(freq: 4000, level: -60)]) == nil)
        #expect(SpectrumAnalysis.inaudibleHint(inaudible: [], peak: 8000) == nil)
        #expect(SpectrumAnalysis.inaudibleHint(inaudible: [10000], peak: 8000)!.contains("direkt neben"))
    }

    @Test func mergeAudiogram() {
        let apple = [HearingPoint(freq: 1000, level: 10), HearingPoint(freq: 8000, level: 40)]
        let app = [HearingPoint(freq: 8000, level: -50), HearingPoint(freq: 12000, level: -30)]
        let m = HearingAnalysis.merge(appleHL: apple, app: app)
        #expect(m.map(\.freq) == [1000, 8000, 12000])
        #expect(m.last?.level == 60)
    }

    @Test func statsAndTrend() {
        let ci = Stats.ci([-1, -2, -1.5, -2.5, -1])
        #expect(ci.hi < 0)
        #expect(Insights.trend([5, 5, 4, 3]) == .down(-1.5))
        #expect(Insights.trend([5, 5]) == .insufficient)
        #expect(abs(Stats.pearson([1, 2, 3], [2, 4, 6]) - 1) < 1e-12)
        #expect(Stats.geoMedian([1000, 4000, 2000]) == 2000)
        let eff = Insights.modeEffects([(.reset, 6, 4), (.reset, 5, 4), (.reset, 6, 5), (.reset, 7, 5), (.reset, 6, 4), (.cr, nil, 3)])
        #expect(eff.count == 1)
        #expect(eff[0].reliable)
    }

    @Test func dailySeriesAndTriggers() {
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 18))!
        var checkins: [Insights.Rating] = []
        var journal: [Insights.JournalValues] = []
        var health: [Insights.HealthDay] = []
        for i in 0..<14 {
            let d = cal.date(byAdding: .day, value: -i, to: now)!
            let short = i % 2 == 0
            checkins.append(.init(ts: d, loudness: short ? 7 : 4, distress: 5))
            journal.append(.init(day: Day.key(d, calendar: cal), loudness: short ? 7 : 4, distress: 5, sleep: short ? 3 : 7, stress: 5, noise: false, caffeine: i % 3 == 0, alcohol: false))
            health.append(.init(day: Day.key(d, calendar: cal), sleepHours: short ? 5 : 8))
        }
        let daily = Insights.daily(days: 14, checkins: checkins, journal: journal, now: now, calendar: cal)
        #expect(daily.count == 14)
        #expect(daily.last?.day == "2026-10-06")
        #expect(daily.last?.loudness == 7)
        let t = Insights.triggers(journal: journal, daily: daily, health: health)
        let night = t.first { $0.label.hasPrefix("Kurze Nacht") }
        #expect(night?.automatic == true)
        #expect(night?.value == 3)
        #expect(night?.isWarning == true)
        let sleep = t.first { $0.label.hasPrefix("Guter Schlaf") }
        #expect((sleep?.value ?? 0) < -0.9)
        // resting HR replaces HRV when a wearable (e.g. Garmin) provides no HRV
        let rhr = (0..<14).map { i in Insights.HealthDay(day: Day.key(cal.date(byAdding: .day, value: -i, to: now)!, calendar: cal), restingHR: i % 2 == 0 && i < 10 ? 70 : 58) }
        #expect(Insights.triggers(journal: [], daily: daily, health: rhr).contains { $0.label.hasPrefix("Erhöhter Ruhepuls") && $0.isWarning })
        #expect(Insights.persistentHighDistress(scores: [30, 65, 70]))
        #expect(!Insights.persistentHighDistress(scores: [70, 40]))
    }

    @Test func routesRoundTrip() {
        let routes: [AppRoute] = [.checkin, .sound(.enrichment), .sound(nil), .play(.enrichment, minutes: 30), .lesson("l3"), .tool("breath"), .body(.jaw), .progress(.weekly), .ri]
        for r in routes { #expect(AppRoute(url: r.url) == r, "\(r.url)") }
        #expect(AppRoute(url: URL(string: "tinnituslab://therapy/reset")!) == .sound(.reset))
        #expect(AppRoute(url: URL(string: "tinnituslab://therapy/enrichment?minutes=30")!) == .play(.enrichment, minutes: 30))
    }

    @Test func plausibility() {
        #expect(Plausibility.correction([(70, 72), (71, 72)]) == nil)
        #expect(Plausibility.correction([(70, 72), (71, 72), (69, 73)]) == -2)
        #expect(Plausibility.correction([(80, 70), (81, 70), (82, 70)]) == 3)
        let c = Plausibility.combinedOffsets(["airPodsPro2": -2, "plaus.airPodsPro2": 1.5, "plaus.wired": 0])
        #expect(c == ["airPodsPro2": -0.5])
    }

    @Test func weeklyScore() {
        #expect(WeeklyContent.score([4, 4, 4, 4, 4, 4, 4, 4]) == 100)
        #expect(WeeklyContent.score([2, 2, 2, 2, 2, 2, 2, 2]) == 50)
    }

    @Test func proseBlocks() {
        let b = Prose.blocks(MindContent.lessons[0].body)
        #expect(b.contains { if case .bullets(let x) = $0 { x.count == 5 } else { false } })
    }

    @Test func bodyContraindications() {
        let all = BodyContent.neck.exercises.count
        let gentle = BodyContent.neck.exercises(excluding: [.acuteNeckPain]).count
        #expect(all == 8)
        #expect(gentle == 4)
        #expect(BodyContent.jaw.exercises(excluding: [.jawLock]).map(\.id) == ["j1", "j3", "j4", "j7", "j8"])
        #expect(BodyContent.neck.minutes() >= 6)
        #expect(BodyContent.neck.exercises.allSatisfy { !$0.cue.isEmpty && $0.steps.count >= 2 })
        #expect(BodyContent.neck.exercises[2].cue(side: 1).hasSuffix("rechts"))
    }
}

@Suite("Web export compatibility")
@MainActor
struct ExportTests {
    let v1 = """
    {"version":1,"settings":{"masterVolume":0.4,"preferredEar":"left","notchWidthOctaves":1,"dailyGoalMin":60,"name":"Tobi","onboarded":false},
     "hearingTests":[{"id":"h1","date":"2026-09-01T10:00:00.000Z","left":[{"freq":1000,"level":-60}],"right":[]}],
     "spectra":[],"matches":[{"id":"m1","date":"2026-09-02T10:00:00.000Z","ear":"left","freq":6200,"trials":[6000,6200,6400],"spreadOctaves":0.05,"loudnessDb":-30,"timbre":"tone","mmlDb":null}],
     "riTrials":[{"id":"r1","date":"2026-09-03T10:00:00.000Z","stimulus":"nbn-third","centerFreq":6200,"levelDb":-25,"durationS":60,"curve":[3,4,5],"baseline":5,"depth":2,"durationOfEffectS":4}],
     "somatic":[],"sessions":[{"id":"s1","date":"2026-09-04T10:00:00.000Z","mode":"bimodal","durationS":600,"pre":5,"post":4,"params":{}},
       {"id":"s2","date":"2026-09-04T11:00:00.000Z","mode":"reset","durationS":700,"pre":5,"post":3,"params":{"level":-20,"source":"pink","stimulus":"nbn-third"}}],
     "checkins":[{"id":"c1","ts":"2026-09-05T07:00:00.000Z","loudness":6,"distress":4}],
     "journal":[{"id":"j1","date":"2026-09-05","loudness":5,"distress":4,"sleep":6,"stress":3,"noiseExposure":true,"caffeine":false,"alcohol":false,"notes":"Konzert"}],
     "weekly":[],"mind":{"lessonsDone":["l1"],"exercises":[{"id":"e1","date":"2026-09-05T08:00:00.000Z","kind":"breath","durationS":180}],"thoughts":[],"spikePlan":"Plan"}}
    """

    @Test func importV1() throws {
        let container = try TinnitusSchema.makeContainer(inMemory: true)
        let ctx = container.mainContext
        try DataTransfer.importData(Data(v1.utf8), into: ctx)
        #expect(ctx.all(TherapySession.self).count == 1, "bimodal session is dropped")
        let s = ctx.settings()
        #expect(s.onboarded, "v1 users with measurements skip onboarding")
        #expect(s.preferredEar == .left)
        #expect(s.lessonsDone == ["l1"])
        #expect(ctx.all(RITrial.self).first?.blind == false)
        #expect(ctx.all(TherapySession.self).first?.params.stimulus == .nbnThird)
        #expect(ctx.latestMatch()?.mmlDb == nil)
        #expect(ctx.all(JournalEntry.self).first?.day == "2026-09-05")
    }

    @Test func exportRoundTripWithExplicitNulls() throws {
        let container = try TinnitusSchema.makeContainer(inMemory: true)
        let ctx = container.mainContext
        try DataTransfer.importData(Data(v1.utf8), into: ctx)
        ctx.insert(TherapySession(mode: .enrichment, durationS: 900, pre: nil, post: 4, params: SessionParams(levelDb: -36, source: .am, origin: .siri)))
        ctx.insert(BodySession(program: .jaw, durationS: 420, completedExercises: 8, gentleOnly: false, jawTension: 3))
        let out = try DataTransfer.exportData(from: ctx)
        let json = String(decoding: out, as: UTF8.self)
        #expect(json.contains("\"mmlDb\" : null"))
        #expect(json.contains("\"pre\" : null"))
        #expect(json.contains("\"version\" : 2"))
        // re-import into a fresh store
        let c2 = try TinnitusSchema.makeContainer(inMemory: true)
        try DataTransfer.importData(out, into: c2.mainContext)
        #expect(c2.mainContext.all(TherapySession.self).count == 2)
        #expect(c2.mainContext.all(BodySession.self).first?.jawTension == 3)
        #expect(c2.mainContext.all(TherapySession.self).contains { $0.params.origin == .siri })
    }

    @Test func rejectsUnknownVersion() {
        #expect(throws: ImportError.self) { try DataTransfer.decode(Data("{\"version\":9}".utf8)) }
    }
}

@Suite("Body rhythm")
struct BodyRhythmTests {
    @Test func phases() {
        let r = Rhythm.hold("Halten", 5, release: 2)
        #expect(r.phase(at: 0).index == 0)
        #expect(r.phase(at: 4.5).left == 0.5)
        #expect(r.phase(at: 5.5).index == 1)
        #expect(r.phase(at: 7.1).index == 0)
        #expect(Rhythm.breath.phase(at: 9).index == 1)
    }
}

@Suite("SwiftData persistence")
@MainActor
struct PersistenceTests {
    /// Composite (Codable struct/enum) attributes must survive a save and a read from a fresh context.
    @Test func compositeAttributesRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tl-\(UUID().uuidString).store")
        let schema = Schema(TinnitusSchema.models)
        let c1 = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let ctx = c1.mainContext
        let rom = NeckROM(rotationLeft: 60, rotationRight: 55, tiltLeft: 30, tiltRight: 28, flexion: 45, extensionDeg: 50)
        let device = DeviceStamp(kind: .airPodsPro2, name: "AirPods Pro", calibrated: true)
        ctx.insert(SomaticTest(results: [SomaticResult(maneuver: .clench, change: 1)], somatic: true, rom: rom))
        ctx.insert(BodySession(program: .neck, durationS: 400, completedExercises: 8, gentleOnly: false, rom: rom))
        ctx.insert(TinnitusMatch(ear: .left, freq: 6000, trials: [6000], spreadOctaves: 0, loudnessDb: -30, timbre: .hiss, mmlDb: nil, device: device))
        ctx.insert(TherapySession(mode: .notched, durationS: 60, pre: 5, post: nil, params: SessionParams(levelDb: -30, source: .music, notchWidthOctaves: 1.5, origin: .siri)))
        ctx.insert(HearingTest(left: [HearingPoint(freq: 1000, level: -60)], right: [], source: .merged, device: device))
        let s = ctx.settings()
        s.calibrationOffsets = ["airPodsPro2": -2]
        s.contraindications = ["jawLock"]
        try ctx.save()

        let c2 = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let ctx2 = ModelContext(c2)
        #expect(ctx2.all(SomaticTest.self).first?.rom == rom)
        #expect(ctx2.all(BodySession.self).first?.rom?.extensionDeg == 50)
        #expect(ctx2.all(TinnitusMatch.self).first?.device == device)
        #expect(ctx2.all(TinnitusMatch.self).first?.timbre == .hiss)
        #expect(ctx2.all(TherapySession.self).first?.params.source == .music)
        #expect(ctx2.all(HearingTest.self).first?.source == .merged)
        #expect(ctx2.settings().calibrationOffsets["airPodsPro2"] == -2)
        #expect(ctx2.settings().contraindications == ["jawLock"])
    }
}

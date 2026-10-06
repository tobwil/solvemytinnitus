#if DEBUG
import Foundation
import SwiftData
import TinnitusCore

/// Realistic 30-day demo data for UI tests, previews and screenshots (launch argument `-demo`).
@MainActor
enum DemoData {
    static func seed(_ ctx: ModelContext) {
        var rng = FastRandom(seed: 2026)
        func r(_ a: Double, _ b: Double) -> Double { a + (b - a) * (rng.bipolar() + 1) / 2 }
        let cal = Calendar.current
        let now = Date.now
        let s = ctx.settings()
        s.onboarded = true
        s.headphonesOk = true
        s.name = "Tobi"
        s.programStart = cal.date(byAdding: .day, value: -24, to: now)
        s.lessonsDone = ["l1", "l2", "l3", "l4"]
        s.contraindications = []
        s.spikePlan = MindContent.spikePlanTemplate
        let device = DeviceStamp(kind: .airPodsPro2, name: "AirPods Pro", calibrated: true)

        let spectrum: [Double: Double] = [1000: 0.5, 2000: 1, 3000: 1.5, 4000: 3, 5000: 5, 6000: 7.5, 8000: 8.5, 10000: 6, 12000: 3.5, 14000: 2, 16000: 1]
        ctx.insert(TinnitusSpectrum(date: cal.date(byAdding: .day, value: -23, to: now)!, ear: .both, timbre: .tone,
                                    points: spectrum.sorted { $0.key < $1.key }.map { SpectrumPoint(freq: $0.key, value: $0.value) }, peak: 8000, device: device))
        for (d, mml) in [(-22, -38.0), (-8, -41.0), (-1, -43.0)] {
            ctx.insert(TinnitusMatch(date: cal.date(byAdding: .day, value: d, to: now)!, ear: .both, freq: 7600, trials: [7400, 7800, 7600],
                                     spreadOctaves: 0.04, loudnessDb: -34, timbre: .tone, mmlDb: mml, device: device))
        }
        let left: [Double: Double] = [500: -78, 1000: -80, 2000: -76, 3000: -72, 4000: -66, 6000: -54, 8000: -50, 10000: -46, 12000: -36, 14000: -24, 16000: -10]
        ctx.insert(HearingTest(date: cal.date(byAdding: .day, value: -21, to: now)!,
                               left: left.sorted { $0.key < $1.key }.map { HearingPoint(freq: $0.key, level: $0.value) },
                               right: left.sorted { $0.key < $1.key }.map { HearingPoint(freq: $0.key, level: $0.value + r(-4, 6)) }, device: device))
        ctx.insert(SomaticTest(date: cal.date(byAdding: .day, value: -20, to: now)!, results: SomaticContent.maneuvers.map { SomaticResult(maneuver: $0.id, change: $0.id == .clench || $0.id == .jawForward ? 1 : 0) },
                               somatic: true, rom: NeckROM(rotationLeft: 62, rotationRight: 58, tiltLeft: 34, tiltRight: 31, flexion: 48, extensionDeg: 52)))
        let depth: [StimulusKind: Double] = [.nbnThird: 3.2, .nbnOctave: 2.1, .amTone: 1.4, .tone: 0.8, .bbn: 1.0, .notchedBbn: 0.2]
        for k in StimulusKind.allCases {
            for i in 0..<2 {
                let dd = max(0, depth[k]! + r(-0.6, 0.6))
                ctx.insert(RITrial(date: cal.date(byAdding: .day, value: -19 + i, to: now)!, stimulus: k, blind: true, centerFreq: 7600, levelDb: -30, durationS: 60,
                                   curve: [6 - dd, 6 - dd * 0.8, 6 - dd * 0.5, 6 - dd * 0.2, 6], baseline: 6, depth: dd, durationOfEffectS: dd * 12, device: device))
            }
        }
        for d in (0...24).reversed() {
            let day = cal.date(byAdding: .day, value: -d, to: now)!
            let trend = 6.5 - Double(24 - d) * 0.06
            let shortNight = d % 5 == 0
            for h in [8, 13, 20] where !(d == 0 && h > cal.component(.hour, from: now)) {
                let ts = cal.date(bySettingHour: h, minute: Int(r(0, 50)), second: 0, of: day)!
                let l = min(10, max(0, (trend + (h == 8 ? 0.6 : h == 20 ? 0.3 : -0.4) + (shortNight ? 1.2 : 0) + r(-0.8, 0.8)).rounded()))
                ctx.insert(CheckIn(ts: ts, loudness: l, distress: max(0, (l - 1.5 + r(-1, 1)).rounded())))
            }
            if d > 0 {
                let l = (trend + (shortNight ? 1 : 0)).rounded()
                ctx.insert(JournalEntry(day: Day.key(day), loudness: l, distress: max(0, l - 2), sleep: shortNight ? 3 : 7, stress: (r(3, 7)).rounded(),
                                        noiseExposure: d % 7 == 3, caffeine: d % 3 == 0, alcohol: d % 6 == 1, notes: d % 7 == 3 ? "Konzert" : ""))
                let snap = HealthSnapshot(day: Day.key(day))
                snap.sleepHours = shortNight ? 5.2 : r(6.8, 8.1)
                snap.hrvMs = shortNight ? r(28, 34) : r(38, 52)
                snap.loudMinutes = d % 7 == 3 ? 95 : r(0, 12)
                snap.headphoneDbA = r(62, 74)
                ctx.insert(snap)
            }
            if d < 20 {
                let reset = day.addingTimeInterval(10 * 3600)
                let pre = (trend + r(-0.5, 0.5)).rounded()
                ctx.insert(TherapySession(date: reset, mode: .reset, durationS: 720, pre: pre, post: max(0, pre - (r(0.5, 2.5)).rounded()), params: SessionParams(levelDb: -30, stimulus: .nbnThird)))
                let pre2 = (trend + r(-0.5, 0.5)).rounded()
                ctx.insert(TherapySession(date: day.addingTimeInterval(21 * 3600), mode: d % 2 == 0 ? .enrichment : .notched, durationS: 2400, pre: pre2, post: max(0, pre2 + (r(-1.2, 0.6)).rounded()),
                                          params: SessionParams(levelDb: -40, source: d % 2 == 0 ? .am : .pink, notchWidthOctaves: 1)))
                if d % 4 == 0 {
                    ctx.insert(TherapySession(date: day.addingTimeInterval(15 * 3600), mode: .cr, durationS: 1200, pre: 6, post: (6 + r(-0.6, 0.6)).rounded(), params: SessionParams(levelDb: -44)))
                }
                ctx.insert(MindExercise(date: day.addingTimeInterval(9 * 3600), kind: d % 2 == 0 ? "breath" : "attention", durationS: 240))
                if d % 2 == 0 {
                    ctx.insert(BodySession(date: day.addingTimeInterval(19 * 3600), program: d % 4 == 0 ? .jaw : .neck, durationS: 480, completedExercises: 8, gentleOnly: false,
                                           rom: d % 8 == 0 ? NeckROM(rotationLeft: 62 + Double(20 - d) * 0.6, rotationRight: 58 + Double(20 - d) * 0.6, tiltLeft: 34, tiltRight: 32, flexion: 48, extensionDeg: 52) : nil,
                                           jawTension: d % 4 == 0 ? 4 : nil))
                }
            }
        }
        for (i, score) in [62, 55, 49].enumerated() {
            ctx.insert(WeeklyCheck(date: cal.date(byAdding: .day, value: -21 + i * 7, to: now)!, answers: Array(repeating: score * 4 * 8 / 100 / 8, count: 8), score: score))
        }
        ctx.insert(ThoughtRecord(date: cal.date(byAdding: .day, value: -6, to: now)!, situation: "Abends im Bett, alles still", thought: "Ich werde heute wieder nicht schlafen",
                                 feeling: 7, alternative: "Ich habe schon oft trotz Tinnitus geschlafen. Ich mache die Klanganreicherung an.", feelingAfter: 4))
        // nothing in the future (today's evening entries)
        for t in ctx.all(TherapySession.self) where t.date > now { ctx.delete(t) }
        for m in ctx.all(MindExercise.self) where m.date > now { ctx.delete(m) }
        for b in ctx.all(BodySession.self) where b.date > now { ctx.delete(b) }
        try? ctx.save()
    }
}
#endif

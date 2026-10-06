import Foundation
import SwiftData
import Testing
import TinnitusCore
@testable import TinnitusLab

@Suite("App logic")
@MainActor
struct AppLogicTests {
    @Test func routingSelectsTabAndPath() {
        let m = AppModel()
        m.open(.ri)
        #expect(m.tab == .me)
        #expect(m.mePath == [.ri])
        m.open(.sound(.reset))
        #expect(m.tab == .practice)
        #expect(m.practicePath == [.sound(.reset)])
        m.open(.lesson("l2"))
        #expect(m.tab == .practice && m.practicePath == [.lesson("l2")])
        m.open(.body(nil))
        #expect(m.tab == .practice && m.practicePath == [.body(nil)])
        m.open(.progress(.weekly))
        #expect(m.tab == .me && m.mePath == [.progress(.weekly)])
        m.push(.learn)
        m.replaceTop(with: .settings)
        #expect(m.mePath == [.progress(.weekly), .settings])
        m.open(.checkin)
        #expect(m.checkInPresented)
    }

    @Test func programStateFromStore() throws {
        let c = try TinnitusSchema.makeContainer(inMemory: true)
        let ctx = c.mainContext
        let s = ctx.settings()
        s.headphonesOk = true
        s.programStart = Calendar.current.date(byAdding: .day, value: -8, to: .now)
        ctx.insert(TinnitusMatch(ear: .both, freq: 6000, trials: [6000], spreadOctaves: 0, loudnessDb: -30, timbre: .tone, mmlDb: -40))
        ctx.insert(CheckIn(loudness: 5, distress: 3))
        ctx.insert(CheckIn(ts: Calendar.current.date(byAdding: .day, value: -1, to: .now)!, loudness: 6, distress: 4))
        ctx.insert(TherapySession(mode: .reset, durationS: 700, pre: 5, post: 3, params: SessionParams(levelDb: -30)))
        ctx.insert(SomaticTest(results: [], somatic: true))
        try ctx.save()
        let st = DataActions.programState(ctx)
        #expect(st.checkinTimes.count == 1, "only today's check-ins")
        #expect(st.sessions.count == 1)
        #expect(st.somatic == true)
        #expect(Program.programWeek(st) == 2)
        let ids = Program.todayTasks(st).map(\.id)
        #expect(ids.contains("body"))
        #expect(ids.contains("reset"))
    }

    @Test func pendingWidgetCheckInsAreImported() throws {
        let c = try TinnitusSchema.makeContainer(inMemory: true)
        let ctx = c.mainContext
        _ = SharedStore.drainPending()
        SharedStore.enqueue(PendingCheckIn(ts: .now, loudness: 4, distress: 2, origin: .widget))
        DataActions.drainPending(ctx)
        let all = ctx.all(CheckIn.self)
        #expect(all.count == 1)
        #expect(all.first?.origin == .widget)
        #expect(SharedStore.pending.isEmpty)
    }

    @Test func sourceLinksAreCheckable() {
        let pub = SourceLinks.url(for: "Fuller et al. 2020, Cochrane")!.absoluteString
        #expect(pub.hasPrefix("https://pubmed.ncbi.nlm.nih.gov/"))
        #expect(pub.contains("Fuller") && pub.contains("2020"))
        #expect(SourceLinks.url(for: "Mazurek et al. 2022, S3-Leitlinie")?.host == "register.awmf.org")
        // every citation in the evidence library resolves to a link
        let all = EvidenceContent.groups.flatMap(\.items).map(\.refs) + SoundContent.modes.map(\.refs) + [BodyContent.refs, MindContent.lessonRefs]
        for r in all.flatMap({ $0.split(separator: ";") }).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            #expect(SourceLinks.url(for: r) != nil, "no link for \(r)")
        }
    }

    @Test func sessionDefaultsFollowMeasurement() {
        let m = TinnitusMatch(ear: .left, freq: 7000, trials: [7000], spreadOctaves: 0, loudnessDb: -30, timbre: .tone, mmlDb: -40)
        let s = AppSettings()
        let cfg = SessionController.defaultConfig(mode: .reset, match: m, settings: s, best: .amTone)
        #expect(cfg.levelDb == -30)
        #expect(cfg.stimulus == .amTone)
        #expect(cfg.ear == .left)
        #expect(cfg.targetMin == 15)
        let e = SessionController.defaultConfig(mode: .enrichment, match: m, settings: s, best: nil)
        #expect(e.levelDb == -46)
        #expect(e.source == .am)
    }
}

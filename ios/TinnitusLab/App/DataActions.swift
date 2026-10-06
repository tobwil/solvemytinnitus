import Foundation
import SwiftData
import TinnitusAudio
import TinnitusCore

/// All writes go through here so that widgets, Health and the watch stay in sync.
@MainActor
enum DataActions {
    static func addCheckIn(_ ctx: ModelContext, loudness: Double, distress: Double, origin: EntryOrigin = .app, at ts: Date = .now) {
        ctx.insert(CheckIn(ts: ts, loudness: loudness, distress: distress, origin: origin))
        try? ctx.save()
        refreshSnapshot(ctx)
    }

    /// Correct a check-in after the fact (wrong tap, second thoughts).
    static func updateCheckIn(_ ctx: ModelContext, _ c: CheckIn, loudness: Double, distress: Double) {
        c.loudness = loudness
        c.distress = distress
        try? ctx.save()
        refreshSnapshot(ctx)
    }

    /// Remove a single entry the user made (check-in, session, exercise).
    static func deleteEntry(_ ctx: ModelContext, _ entry: any PersistentModel) {
        ctx.delete(entry)
        try? ctx.save()
        refreshSnapshot(ctx)
    }

    static func logMind(_ ctx: ModelContext, kind: String, durationS: Double, origin: EntryOrigin = .app, mindful: Bool = false) {
        let end = Date.now
        ctx.insert(MindExercise(date: end, kind: kind, durationS: durationS, origin: origin))
        try? ctx.save()
        if mindful && durationS >= 30 && ctx.settings().useHealthKit {
            Task { await HealthService.shared.saveMindful(start: end.addingTimeInterval(-durationS), end: end) }
        }
        refreshSnapshot(ctx)
    }

    static func completeLesson(_ ctx: ModelContext, _ id: String, durationS: Double) {
        let s = ctx.settings()
        if !s.lessonsDone.contains(id) { s.lessonsDone.append(id) }
        logMind(ctx, kind: "lesson:\(id)", durationS: durationS)
    }

    static func saveSession(_ ctx: ModelContext, mode: TherapyMode, durationS: Double, pre: Double?, post: Double?, params: SessionParams) {
        ctx.insert(TherapySession(date: .now, mode: mode, durationS: durationS, pre: pre, post: post, params: params))
        try? ctx.save()
        refreshSnapshot(ctx)
    }

    static func saveBody(_ ctx: ModelContext, _ s: BodySession) {
        ctx.insert(s)
        try? ctx.save()
        if ctx.settings().useHealthKit && s.durationS >= 60 {
            let end = Date.now
            Task { await HealthService.shared.saveMindful(start: end.addingTimeInterval(-s.durationS), end: end) }
        }
        refreshSnapshot(ctx)
    }

    /// Imports check-ins queued by widgets/Siri while the app was not running.
    static func drainPending(_ ctx: ModelContext) {
        let pending = SharedStore.drainPending()
        guard !pending.isEmpty else { return }
        for p in pending { ctx.insert(CheckIn(ts: p.ts, loudness: p.loudness, distress: p.distress, origin: p.origin)) }
        try? ctx.save()
        refreshSnapshot(ctx)
    }

    /// ProgramState from the store (for Heute, widgets, watch).
    static func programState(_ ctx: ModelContext, now: Date = .now) -> ProgramState {
        let s = ctx.settings()
        let since = Calendar.current.startOfDay(for: now)
        let todayCheckins = (try? ctx.fetch(FetchDescriptor<CheckIn>(predicate: #Predicate { $0.ts >= since }))) ?? []
        let todaySessions = (try? ctx.fetch(FetchDescriptor<TherapySession>(predicate: #Predicate { $0.date >= since }))) ?? []
        let todayMind = (try? ctx.fetch(FetchDescriptor<MindExercise>(predicate: #Predicate { $0.date >= since }))) ?? []
        let todayBody = (try? ctx.fetch(FetchDescriptor<BodySession>(predicate: #Predicate { $0.date >= since }))) ?? []
        let dayKey = Day.key(now)
        let journalToday = (try? ctx.fetchCount(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.day == dayKey }))) ?? 0
        let match = ctx.latestMatch()
        let riCount = (try? ctx.fetchCount(FetchDescriptor<RITrial>())) ?? 0
        return ProgramState(
            now: now,
            programStart: s.programStart,
            headphonesOk: s.headphonesOk,
            dailyGoalMin: s.dailyGoalMin,
            spectrumPeak: ctx.latestSpectrum()?.peak,
            match: match.map { ($0.freq, $0.mmlDb) },
            hasHearing: ctx.latestHearing() != nil,
            somatic: ctx.latestSomatic()?.somatic,
            riTrialCount: riCount,
            checkinTimes: todayCheckins.map(\.ts),
            sessions: todaySessions.map { ($0.date, $0.mode, $0.durationS) },
            mindDates: todayMind.map(\.date),
            bodyDates: todayBody.map(\.date),
            journalDays: journalToday > 0 ? [dayKey] : []
        )
    }

    static func refreshSnapshot(_ ctx: ModelContext) {
        let st = programState(ctx)
        let tasks = Program.todayTasks(st)
        let since = Calendar.current.startOfDay(for: .now)
        let last = (try? ctx.fetch(FetchDescriptor<CheckIn>(predicate: #Predicate { $0.ts >= since }, sortBy: [SortDescriptor(\.ts, order: .reverse)])))?.first
        let soundMin = Int((st.sessions.filter { $0.mode != .reset }.reduce(0) { $0 + $1.durationS } / 60).rounded())
        let snap = WidgetSnapshot(
            day: Day.key(),
            checkinsToday: st.checkinTimes.count,
            lastLoudness: last?.loudness,
            tasksDone: tasks.filter(\.done).count,
            tasksTotal: tasks.count,
            soundMinutesToday: soundMin,
            programDay: Program.programDay(st),
            programWeek: Program.programWeek(st),
            spikePlan: ctx.settings().spikePlan,
            tinnitusHz: st.match?.freq,
            updatedAt: .now
        )
        if snap != SharedStore.snapshot {
            SharedStore.snapshot = snap
            SharedStore.reloadWidgets()
        }
        WatchBridge.shared.sendContext(snap)
        var newest = FetchDescriptor<CheckIn>(sortBy: [SortDescriptor(\.ts, order: .reverse)])
        newest.fetchLimit = 1
        let latest = (try? ctx.fetch(newest))?.first
        Ambient.shared.update(loudness: latest?.loudness, at: latest?.ts)
    }

    // MARK: Calibration helpers

    static func applyAudioSettings(_ s: AppSettings) {
        let e = AudioEngine.shared
        e.masterVolume = s.masterVolume
        e.userOffsets = Plausibility.combinedOffsets(s.calibrationOffsets)
    }
}

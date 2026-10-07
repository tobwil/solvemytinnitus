import SwiftData
import SwiftUI
import TinnitusAudio
import TinnitusCore

@main
struct TinnitusLabApp: App {
    @State private var model = AppModel()
    private let container: ModelContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // CloudKit sync when the iCloud entitlement is provisioned; otherwise a local store.
        let isUITest = ProcessInfo.processInfo.arguments.contains("-uitest")
        if isUITest, let c = try? TinnitusSchema.makeContainer(inMemory: true) {
            container = c
        } else if let c = try? TinnitusSchema.makeContainer(cloud: SharedStore.iCloudSync) {
            container = c
        } else if let c = try? TinnitusSchema.makeContainer(cloud: false) {
            container = c
        } else {
            container = try! TinnitusSchema.makeContainer(inMemory: true)
        }
        let args = ProcessInfo.processInfo.arguments
        if isUITest, args.contains("-onboarded") {
            let s = container.mainContext.settings()
            s.onboarded = true
            s.headphonesOk = true
            s.programStart = .now
            try? container.mainContext.save()
        }
        #if DEBUG
        if args.contains("-demo"), (try? container.mainContext.fetchCount(FetchDescriptor<CheckIn>())) == 0 {
            DemoData.seed(container.mainContext)
        }
        #endif
        SessionController.shared.container = container
        // Notification delegate before launch finishes, so a tap that cold-launches the app is delivered.
        ReminderService.shared.setUp()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(container)
                .onOpenURL { url in
                    if let r = AppRoute(url: url) { model.open(r) }
                }
                .task { await launch() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { becameActive() }
        }
    }

    @MainActor
    private func launch() async {
        let ctx = container.mainContext
        let s = ctx.settings()
        DataActions.applyAudioSettings(s)
        SessionController.shared.setUp()
        ReminderService.shared.onOpen = { model.open($0) }
        CheckInSink.handler = { l, d, origin in
            DataActions.addCheckIn(ctx, loudness: l, distress: d, origin: origin)
        }
        model.onPlay = { mode, minutes in _ = startSound(mode: mode, minutes: minutes, origin: .widget) }
        SessionStopSink.handler = { SessionController.shared.finish(auto: false) }
        SoundIntentSink.handler = { mode, minutes, origin in
            startSound(mode: mode, minutes: minutes, origin: origin)
        }
        WatchBridge.shared.onCheckIn = { l, d, ts in DataActions.addCheckIn(ctx, loudness: l, distress: d, origin: .watch, at: ts) }
        WatchBridge.shared.onBreath = { dur, _ in DataActions.logMind(ctx, kind: "breath", durationS: dur, origin: .watch) }
        WatchBridge.shared.onStartSound = { mode, minutes in startSound(mode: mode, minutes: minutes, origin: .watch) }
        WatchBridge.shared.onStopSound = { SessionController.shared.finish(auto: false) }
        WatchBridge.shared.activate()
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SessionController.shared.endActivitiesOnTermination() }
        }
        becameActive()
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-route"), i + 1 < args.count, let url = URL(string: args[i + 1]), let r = AppRoute(url: url) {
            model.open(r)
        }
        #if DEBUG
        // screenshots: -tab practice|me opens a room directly
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count, let t = AppTab(rawValue: args[i + 1]) {
            model.tab = t
        }
        #endif
        if s.remindersOn || s.sessionRemindersOn || s.lessonReminderOn {
            await ReminderService.shared.reschedule(checkins: s.remindersOn, windows: s.reminderWindows, sessions: s.sessionRemindersOn, lesson: s.lessonReminderOn)
        }
    }

    @MainActor
    private func becameActive() {
        SessionController.shared.cleanUpOrphanedActivities()
        let ctx = container.mainContext
        DataActions.drainPending(ctx)
        DataActions.refreshSnapshot(ctx)
        if ctx.settings().useHealthKit {
            Task {
                await HealthService.shared.sync(into: ctx, days: 14)
                await HealthService.shared.plausibilityCheck(ctx)
                DataActions.applyAudioSettings(ctx.settings())
            }
        }
    }

    /// Siri, Shortcuts, sleep focus automation and the watch start sessions here.
    @MainActor
    private func startSound(mode: TherapyMode, minutes: Int, origin: EntryOrigin) -> Bool {
        let ctx = container.mainContext
        guard let match = ctx.latestMatch() else { return false }
        let best = RIAnalysis.best(ctx.all(RITrial.self).map { .init(stimulus: $0.stimulus, depth: $0.depth, durationOfEffectS: $0.durationOfEffectS) })
        var cfg = SessionController.defaultConfig(mode: mode, match: match, settings: ctx.settings(), best: best?.stimulus)
        cfg.targetMin = minutes
        SessionController.shared.start(cfg, origin: origin)
        return true
    }
}

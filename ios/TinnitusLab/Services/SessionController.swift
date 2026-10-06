import ActivityKit
import Foundation
import Observation
import SwiftData
import TinnitusAudio
import TinnitusCore
import UIKit

/// Runs sound sessions independent of any screen: background audio, sleep timer with 60 s fade,
/// interruptions, route changes, lock screen controls and Live Activity (04-module "Klang").
@MainActor
@Observable
final class SessionController {
    static let shared = SessionController()

    enum State: Equatable { case idle, running, paused }

    struct Config: Equatable {
        var mode: TherapyMode
        var freq: Double
        var ear: Ear
        var levelDb: Double
        var source: SoundSource
        var stimulus: StimulusKind
        var widthOctaves: Double
        var onS: Double = 30
        var offS: Double = 60
        /// 0 = open-ended.
        var targetMin: Int
        var mmlDb: Double?
        var loudnessDb: Double
    }

    /// A finished session waiting for the after-rating.
    struct RatingRequest: Identifiable, Equatable {
        var sessionUID: String
        var title: String
        var durationS: Double
        var pre: Double?
        var id: String { sessionUID }
    }

    private(set) var state: State = .idle
    private(set) var config: Config?
    private(set) var elapsed: Double = 0
    private(set) var phase = "Bereit"
    private(set) var silence = false
    private(set) var fading = false
    private(set) var origin: EntryOrigin = .app
    private(set) var pre: Double?
    var ratingRequest: RatingRequest?
    /// Short status messages for the UI (route lost, dose warning …).
    var message: String?
    var music: MusicLoader.Decoded?

    @ObservationIgnored var container: ModelContainer?
    @ObservationIgnored private var voice: (any SoundVoice)?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var resetTask: Task<Void, Never>?
    @ObservationIgnored private var interruptedWhileRunning = false
    @ObservationIgnored private var activity: Activity<SessionActivityAttributes>?
    @ObservationIgnored private var startDate = Date.now
    /// Energy accumulator for the session's estimated level.
    @ObservationIgnored private var splEnergy = 0.0
    @ObservationIgnored private var splSeconds = 0.0
    /// Posture hint (06): seconds with the head tilted forward, and whether this session started tracking.
    @ObservationIgnored private var forwardSeconds = 0.0
    @ObservationIgnored private var trackingPosture = false
    @ObservationIgnored private var lastPostureHint = Date.distantPast

    var isActive: Bool { state != .idle }
    var title: String { config.map { SoundContent.mode($0.mode).title } ?? "" }

    var remaining: Double? {
        guard let c = config, c.targetMin > 0 else { return nil }
        return max(0, Double(c.targetMin * 60) - elapsed)
    }

    var progress: Double {
        guard let c = config, c.targetMin > 0 else { return 0 }
        return min(1, elapsed / Double(c.targetMin * 60))
    }

    private var engine: AudioEngine { AudioEngine.shared }

    func setUp() {
        engine.onInterruption = { [weak self] began, shouldResume in
            guard let self else { return }
            if began {
                if self.state == .running {
                    self.interruptedWhileRunning = true
                    self.pause()
                }
            } else if self.interruptedWhileRunning {
                self.interruptedWhileRunning = false
                // resume automatically only for enrichment, never for measurements
                if shouldResume, self.config?.mode == .enrichment { self.resume() }
            }
        }
        engine.onRouteLost = { [weak self] in
            guard let self, self.state == .running else { return }
            self.pause()
            self.message = "Kopfhörer getrennt – Sitzung pausiert."
        }
        engine.onDoseWarning = { [weak self] frac in
            self?.message = "Hörschutz: Du hast heute \(Int(frac * 100)) % deiner Tagesdosis erreicht. Leiser ist genauso wirksam."
        }
        NowPlaying.shared.onPlay = { [weak self] in self?.resume() }
        NowPlaying.shared.onPause = { [weak self] in self?.pause() }
        NowPlaying.shared.onStop = { [weak self] in self?.finish(auto: false) }
    }

    /// Default configuration for a mode from the latest measurement.
    static func defaultConfig(mode: TherapyMode, match: TinnitusMatch, settings: AppSettings, best: StimulusKind?) -> Config {
        Config(mode: mode, freq: match.freq, ear: match.ear,
               levelDb: SoundContent.defaultLevel(mode: mode, mmlDb: match.mmlDb, loudnessDb: match.loudnessDb),
               source: SoundContent.defaultSource(mode), stimulus: best ?? .nbnThird,
               widthOctaves: settings.notchWidthOctaves, targetMin: SoundContent.defaultMinutes(mode),
               mmlDb: match.mmlDb, loudnessDb: match.loudnessDb)
    }

    // MARK: Control

    func start(_ c: Config, origin: EntryOrigin = .app, pre: Double? = nil) {
        if isActive { finish(auto: false) }
        config = c
        self.origin = origin
        self.pre = pre
        elapsed = 0
        fading = false
        message = nil
        startDate = .now
        splEnergy = 0
        splSeconds = 0
        let mix = c.mode == .enrichment && (container?.mainContext.settings().mixWithOthers ?? false)
        engine.configureSession(mixWithOthers: mix)
        startVoices()
        state = .running
        startTicking()
        startActivity()
        updateNowPlaying()
        forwardSeconds = 0
        if container?.mainContext.settings().postureHint == true, HeadTracker.shared.isAvailable, !HeadTracker.shared.running {
            HeadTracker.shared.start()
            trackingPosture = true
        }
    }

    func pause() {
        guard state == .running else { return }
        stopVoices(fadeMs: 300)
        tickTask?.cancel()
        tickTask = nil
        state = .paused
        phase = "Pausiert"
        updateActivity()
        updateNowPlaying()
    }

    func resume() {
        guard state == .paused, config != nil else { return }
        try? engine.ensureRunning()
        startVoices()
        state = .running
        startTicking()
        updateActivity()
        updateNowPlaying()
    }

    func toggle() { state == .running ? pause() : resume() }

    func setLevel(_ db: Double) {
        config?.levelDb = db
        voice?.setLevel(db)
    }

    /// Changes that need new voices (source, notch width, stimulus) restart them.
    func update(_ change: (inout Config) -> Void) {
        guard var c = config else { return }
        change(&c)
        config = c
        if state == .running {
            stopVoices(fadeMs: 200)
            startVoices()
        }
    }

    func setTarget(minutes: Int) {
        config?.targetMin = minutes
        fading = false
        updateActivity()
    }

    /// Ends the session. Saves it if it lasted ≥ 20 s; asks for the after-rating when started in the app.
    func finish(auto: Bool) {
        guard let c = config else { return }
        stopVoices(fadeMs: auto ? 50 : 300)
        tickTask?.cancel()
        tickTask = nil
        if auto { engine.chime(levelDb: -30) }
        let duration = elapsed
        if duration >= 20, let ctx = container?.mainContext {
            let params = SessionParams(levelDb: c.levelDb, source: c.mode == .enrichment || c.mode == .notched ? c.source : nil,
                                       stimulus: c.mode == .reset ? c.stimulus : nil,
                                       notchWidthOctaves: c.mode == .notched ? c.widthOctaves : nil, origin: origin,
                                       estimatedSPL: splSeconds > 0 ? 10 * log10(splEnergy / splSeconds) : nil, device: engine.deviceKind)
            let s = TherapySession(date: .now, mode: c.mode, durationS: duration, pre: pre, post: nil, params: params)
            ctx.insert(s)
            try? ctx.save()
            DataActions.refreshSnapshot(ctx)
            // sessions from Siri/sleep focus/watch skip the rating (04-module)
            if origin == .app { ratingRequest = RatingRequest(sessionUID: s.uid, title: SoundContent.mode(c.mode).title, durationS: duration, pre: pre) }
        } else if duration > 0 && duration < 20 && !auto {
            message = "Zu kurz zum Speichern."
        }
        if trackingPosture {
            HeadTracker.shared.stop()
            trackingPosture = false
        }
        state = .idle
        config = nil
        phase = "Bereit"
        silence = false
        music = nil
        endActivity()
        NowPlaying.shared.clear()
        WatchBridge.shared.sendContext(SharedStore.snapshot, playing: false)
    }

    /// Stores the after-rating for the saved session.
    func rate(_ post: Double?) {
        guard let req = ratingRequest, let ctx = container?.mainContext else { ratingRequest = nil; return }
        let uid = req.sessionUID
        if let post, let s = try? ctx.fetch(FetchDescriptor<TherapySession>(predicate: #Predicate { $0.uid == uid })).first {
            s.post = post
            try? ctx.save()
        }
        ratingRequest = nil
    }

    // MARK: Voices

    private func startVoices() {
        guard let c = config else { return }
        switch c.mode {
        case .enrichment:
            let recipe: Recipe = switch c.source {
            case .am: .amNoise(center: c.freq)
            case .rain: .rain
            case .brown: .noise(.brown)
            case .white: .noise(.white)
            default: .noise(.pink)
            }
            phase = c.source == .am ? "AM-Rauschen 10 Hz" : c.source.label
            voice = engine.play(recipe, ear: c.ear, levelDb: c.levelDb, purpose: .sound)
        case .notched:
            if c.source == .music, let m = music {
                phase = m.title
                voice = try? engine.playMusic(samples: m.samples, sampleRate: m.sampleRate, ear: c.ear, levelDb: c.levelDb)
            } else {
                let recipe: Recipe = c.source == .rain
                    ? .notchedRain(center: c.freq, widthOctaves: c.widthOctaves)
                    : .notchedNoise(c.source == .white ? .white : c.source == .brown ? .brown : .pink, center: c.freq, widthOctaves: c.widthOctaves)
                phase = c.source == .rain ? "Regen mit Lücke" : "Rauschen mit Lücke"
                voice = engine.play(recipe, ear: c.ear, levelDb: c.levelDb, purpose: .sound)
            }
        case .cr:
            phase = "4 Töne · 1,5 Hz"
            voice = engine.play(.cr(ft: c.freq), ear: c.ear, levelDb: c.levelDb, purpose: .sound)
        case .reset:
            startResetCycles()
        }
    }

    private func stopVoices(fadeMs: Double) {
        resetTask?.cancel()
        resetTask = nil
        voice?.stop(fadeMs: fadeMs)
        voice = nil
    }

    /// Best RI sound alternating with silence.
    private func startResetCycles() {
        guard let c = config else { return }
        let cap = SafetyLimits.riCap(mmlDb: c.mmlDb, loudnessDb: c.loudnessDb)
        resetTask = Task { @MainActor [weak self] in
            var cycle = 0
            while !Task.isCancelled {
                guard let self, let c = self.config else { return }
                cycle += 1
                self.silence = false
                self.phase = "Zyklus \(cycle) · Klang"
                self.updateActivity()
                self.voice = self.engine.play(Recipe.stimulus(c.stimulus, freq: c.freq, notchWidth: c.widthOctaves), ear: c.ear, levelDb: c.levelDb, purpose: .sound, extraCapDb: cap)
                try? await Task.sleep(for: .seconds(c.onS))
                if Task.isCancelled { return }
                self.voice?.stop(fadeMs: 600)
                self.voice = nil
                self.silence = true
                self.phase = "Zyklus \(cycle) · Stille – achte auf die Veränderung"
                self.updateActivity()
                try? await Task.sleep(for: .seconds(c.offS))
            }
        }
    }

    // MARK: Clock

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { @MainActor [weak self] in
            var last = Date.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.state == .running else { return }
                let now = Date.now
                let dt = now.timeIntervalSince(last)
                self.elapsed += dt
                last = now
                if let spl = self.engine.estimatedSPL {
                    self.splEnergy += dt * pow(10, spl / 10)
                    self.splSeconds += dt
                }
                self.checkPosture(dt: dt)
                if let rem = self.remaining {
                    // sleep timer: fade out over the last 60 s
                    if rem <= 60 && !self.fading && rem > 0 {
                        self.fading = true
                        self.resetTask?.cancel()
                        self.voice?.stop(fadeMs: rem * 1000)
                        self.phase = "Klingt aus …"
                        self.updateActivity()
                    }
                    if rem <= 0 {
                        self.finish(auto: true)
                        return
                    }
                }
                if Int(self.elapsed) % 10 == 0 { self.updateNowPlaying() }
            }
        }
    }

    /// Head tilted forward > 20° for 3 minutes → silent haptic reminder (at most every 10 minutes).
    private func checkPosture(dt: Double) {
        let t = HeadTracker.shared
        guard trackingPosture, t.connected else { return }
        forwardSeconds = t.pitch > 20 ? forwardSeconds + dt : 0
        if forwardSeconds >= 180, Date.now.timeIntervalSince(lastPostureHint) > 600 {
            lastPostureHint = .now
            forwardSeconds = 0
            Haptics.soft()
            message = "Haltung: Dein Kopf ist seit ein paar Minuten nach vorn geneigt. Kurz aufrichten, Kinn sanft zurück, Schultern sinken lassen."
        }
    }

    // MARK: Lock screen & Live Activity

    private func updateNowPlaying() {
        guard let c = config else { return }
        NowPlaying.shared.update(title: SoundContent.mode(c.mode).title, subtitle: phase, elapsed: elapsed, duration: c.targetMin > 0 ? Double(c.targetMin * 60) : nil, playing: state == .running)
    }

    private var contentState: SessionActivityAttributes.ContentState {
        let rem = remaining
        return SessionActivityAttributes.ContentState(
            phase: phase,
            endDate: state == .running ? rem.map { Date.now.addingTimeInterval($0) } : nil,
            startDate: Date.now.addingTimeInterval(-elapsed),
            paused: state == .paused,
            remainingWhenPaused: state == .paused ? rem : nil,
            silence: silence
        )
    }

    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let c = config else { return }
        // never more than one: end anything left over from an earlier run first
        Self.endAllActivities()
        let attrs = SessionActivityAttributes(title: SoundContent.mode(c.mode).title, symbol: SoundContent.mode(c.mode).symbol)
        let st = contentState
        activity = try? Activity.request(attributes: attrs, content: .init(state: st, staleDate: Self.staleDate(st)))
    }

    /// The activity turns stale at the planned end, so a killed app never leaves a running countdown.
    private static func staleDate(_ st: SessionActivityAttributes.ContentState) -> Date? {
        st.endDate.map { $0.addingTimeInterval(2) }
    }

    private func updateActivity() {
        guard let id = activity?.id else { return }
        let st = contentState
        Task {
            for a in Activity<SessionActivityAttributes>.activities where a.id == id {
                await a.update(.init(state: st, staleDate: Self.staleDate(st)))
            }
        }
    }

    private func endActivity() {
        activity = nil
        Self.endAllActivities()
    }

    /// Ends every session activity of this app. Runs inside a background task so it completes even
    /// if the app is closed right after stopping.
    static func endAllActivities() {
        guard !Activity<SessionActivityAttributes>.activities.isEmpty else { return }
        let app = UIApplication.shared
        var bg = UIBackgroundTaskIdentifier.invalid
        bg = app.beginBackgroundTask(withName: "end-live-activity") { app.endBackgroundTask(bg) }
        let token = bg
        Task.detached {
            for a in Activity<SessionActivityAttributes>.activities {
                await a.end(nil, dismissalPolicy: .immediate)
            }
            await MainActor.run { UIApplication.shared.endBackgroundTask(token) }
        }
    }

    /// Called on launch and whenever the app becomes active: removes activities that no running
    /// session belongs to (e.g. after the app was closed from the app switcher).
    func cleanUpOrphanedActivities() {
        if state == .idle { Self.endAllActivities() }
    }

    /// Best effort when the system terminates the app: end the activity before the process goes away.
    func endActivitiesOnTermination() {
        let sem = DispatchSemaphore(value: 0)
        Task.detached {
            for a in Activity<SessionActivityAttributes>.activities {
                await a.end(nil, dismissalPolicy: .immediate)
            }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 1.5)
    }
}

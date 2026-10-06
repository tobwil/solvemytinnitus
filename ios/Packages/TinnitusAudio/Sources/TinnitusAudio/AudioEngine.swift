import AVFoundation
import Observation
import TinnitusCore

/// Render-thread state of one voice. Only touched from the source node's render block.
final class VoiceRenderer: @unchecked Sendable {
    private var voice: SynthVoice
    private let gl: Float
    private let gr: Float
    private let scratch: UnsafeMutablePointer<Float>
    private static let chunk = 4096

    init(voice: SynthVoice, ear: Ear) {
        self.voice = voice
        (gl, gr) = ear.gains
        scratch = .allocate(capacity: Self.chunk)
    }

    deinit { scratch.deallocate() }

    func render(frames: Int, into abl: UnsafeMutableAudioBufferListPointer) {
        let l = abl[0].mData?.assumingMemoryBound(to: Float.self)
        let r = abl.count > 1 ? abl[1].mData?.assumingMemoryBound(to: Float.self) : nil
        var done = 0
        while done < frames {
            let k = min(Self.chunk, frames - done)
            voice.render(into: scratch, frames: k)
            for i in 0..<k {
                let s = scratch[i]
                l?[done + i] = s * gl
                r?[done + i] = s * gr
            }
            done += k
        }
    }
}

/// Something that is currently sounding (synthesised voice or music player).
@MainActor
public protocol SoundVoice: AnyObject {
    var levelDb: Double { get }
    var isFinished: Bool { get }
    var purpose: SoundPurpose { get }
    /// Dominant frequency for level estimation (0 = broadband).
    var frequencyHint: Double { get }
    func setLevel(_ db: Double)
    func stop(fadeMs: Double)
    func applyCap(_ capDb: Double)
}

@MainActor
public final class VoiceHandle: SoundVoice {
    public let control: VoiceControl
    public let recipe: Recipe
    public let purpose: SoundPurpose
    public private(set) var frequencyHint: Double
    let node: AVAudioSourceNode
    private let extraCap: Double?
    weak var owner: AudioEngine?

    init(control: VoiceControl, recipe: Recipe, purpose: SoundPurpose, frequencyHint: Double, node: AVAudioSourceNode, extraCap: Double?, owner: AudioEngine) {
        self.control = control
        self.recipe = recipe
        self.purpose = purpose
        self.frequencyHint = frequencyHint
        self.node = node
        self.extraCap = extraCap
        self.owner = owner
    }

    public var levelDb: Double { control.levelDb }
    public var isFinished: Bool { control.isFinished }
    /// Effective level after the safety cap.
    public var effectiveLevelDb: Double { min(control.levelDb, control.capDb) }
    public var isCapped: Bool { control.levelDb > control.capDb + 0.01 }

    public func setLevel(_ db: Double) { control.levelDb = db }

    public func setFrequency(_ f: Double) {
        control.frequency = f
        frequencyHint = f
        owner?.refreshCaps()
    }

    public func stop(fadeMs: Double = 30) { control.stop(fadeMs: fadeMs) }

    public func applyCap(_ capDb: Double) {
        control.capDb = min(capDb, extraCap ?? .infinity)
    }
}

/// Music (DRM-free file) pre-rendered through the notch and looped by a player node.
@MainActor
public final class PlayerVoice: SoundVoice {
    let player: AVAudioPlayerNode
    public let purpose: SoundPurpose = .sound
    public let frequencyHint: Double = 0
    public private(set) var levelDb: Double
    public private(set) var isFinished = false
    private var cap: Double = SafetyLimits.absoluteMaxDbfs
    private var fadeTask: Task<Void, Never>?
    weak var owner: AudioEngine?

    init(player: AVAudioPlayerNode, levelDb: Double, owner: AudioEngine) {
        self.player = player
        self.levelDb = levelDb
        self.owner = owner
    }

    private var targetGain: Float { Float(Level.dbToGain(min(levelDb, cap))) }

    public func setLevel(_ db: Double) {
        levelDb = db
        if fadeTask == nil { player.volume = targetGain }
    }

    public func applyCap(_ capDb: Double) {
        cap = capDb
        if fadeTask == nil { player.volume = targetGain }
    }

    func fadeIn(ms: Double = 300) { fade(to: targetGain, ms: ms, then: nil) }

    public func stop(fadeMs: Double = 300) {
        fade(to: 0, ms: fadeMs) { [weak self] in
            guard let self else { return }
            self.player.stop()
            self.isFinished = true
            self.owner?.reap()
        }
    }

    private func fade(to target: Float, ms: Double, then done: (@MainActor () -> Void)?) {
        fadeTask?.cancel()
        let start = player.volume
        let steps = max(1, Int(ms / 20))
        fadeTask = Task { @MainActor [weak self] in
            for i in 1...steps {
                try? await Task.sleep(for: .milliseconds(20))
                guard let self, !Task.isCancelled else { return }
                self.player.volume = start + (target - start) * Float(i) / Float(steps)
            }
            self?.fadeTask = nil
            done?()
        }
    }
}

/// Central audio engine (05-audio-engine):
/// [voices] → submix → peak limiter → main mixer (app volume) → output, with an analyser tap.
@MainActor
@Observable
public final class AudioEngine {
    public static let shared = AudioEngine()

    @ObservationIgnored let engine = AVAudioEngine()
    @ObservationIgnored let submix = AVAudioMixerNode()
    @ObservationIgnored let limiter: AVAudioUnitEffect
    @ObservationIgnored public let analyzer = SpectrumAnalyzer()
    @ObservationIgnored public let dose = DoseMeter()
    @ObservationIgnored private var voices: [any SoundVoice] = []
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var volumeObservation: NSKeyValueObservation?
    @ObservationIgnored private let manual: Bool
    @ObservationIgnored private var tapInstalled = false

    public private(set) var route: AudioRouteInfo = .none
    public private(set) var systemVolume: Double = 0.5
    public private(set) var doseToday: Double = 0
    public private(set) var activeVoiceCount = 0
    /// Exact model picked by the user when the name is ambiguous (e.g. AirPods Pro 3).
    public var deviceOverride: DeviceKind? { didSet { refreshCaps() } }
    /// Personal offsets from the 1 kHz anchor, keyed by `DeviceKind.rawValue`.
    public var userOffsets: [String: Double] = [:] { didSet { refreshCaps() } }
    public var masterVolume: Double = 0.5 {
        didSet {
            engine.mainMixerNode.outputVolume = Float(min(1, max(0, masterVolume)))
            refreshCaps()
        }
    }

    /// Called when the headphones were unplugged (old device unavailable).
    @ObservationIgnored public var onRouteLost: (@MainActor () -> Void)?
    /// (began, shouldResume)
    @ObservationIgnored public var onInterruption: (@MainActor (Bool, Bool) -> Void)?
    /// Called once when today's dose crosses 50 %.
    @ObservationIgnored public var onDoseWarning: (@MainActor (Double) -> Void)?
    @ObservationIgnored private var doseWarned = false

    public init(manualRendering: Bool = false, sampleRate: Double = 48000) {
        manual = manualRendering
        let desc = AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        limiter = AVAudioUnitEffect(audioComponentDescription: desc)
        if manualRendering {
            let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
            try? engine.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: 4096)
        }
        engine.attach(submix)
        engine.attach(limiter)
        let fmt = AVAudioFormat(standardFormatWithSampleRate: self.sampleRate, channels: 2)
        engine.connect(submix, to: limiter, format: fmt)
        engine.connect(limiter, to: engine.mainMixerNode, format: fmt)
        engine.mainMixerNode.outputVolume = Float(masterVolume)
        #if os(iOS)
        if !manualRendering { observeSession() }
        #endif
        route = AudioRouteInfo.current()
        doseToday = dose.today()
    }

    public var sampleRate: Double {
        if manual { return engine.manualRenderingFormat.sampleRate }
        let sr = engine.outputNode.outputFormat(forBus: 0).sampleRate
        return sr > 0 ? sr : 48000
    }

    public var deviceKind: DeviceKind { deviceOverride ?? route.kind }
    public var profile: DeviceProfile { DeviceProfile.profile(for: deviceKind) }
    public var deviceStamp: DeviceStamp {
        DeviceStamp(kind: deviceKind, name: route.name, calibrated: profile.calibrated)
    }

    public var estimator: LevelEstimator {
        LevelEstimator(profile: profile, masterVolume: masterVolume, systemVolume: systemVolume, userOffset: userOffsets[deviceKind.rawValue] ?? 0)
    }

    public var isPlaying: Bool { activeVoiceCount > 0 }
    public var canMeasure: Bool { SafetyLimits.allowsMeasurement(deviceKind) }

    // MARK: Session

    /// `.playback` so sound continues with the screen locked; mixing only for enrichment.
    public func configureSession(mixWithOthers: Bool = false) {
        #if os(iOS)
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, options: mixWithOthers ? [.mixWithOthers] : [])
        try? s.setActive(true)
        systemVolume = Double(s.outputVolume)
        route = AudioRouteInfo.current()
        refreshCaps()
        #endif
    }

    public func ensureRunning() throws {
        guard !engine.isRunning else { return }
        #if os(iOS)
        if !manual {
            let s = AVAudioSession.sharedInstance()
            if s.category != .playback { configureSession() }
            try? s.setActive(true)
        }
        #endif
        engine.prepare()
        try engine.start()
    }

    // MARK: Playback

    @discardableResult
    public func play(_ recipe: Recipe, ear: Ear, levelDb: Double, purpose: SoundPurpose, extraCapDb: Double? = nil) -> VoiceHandle {
        try? ensureRunning()
        let fs = sampleRate
        let hint: Double = switch recipe {
        case .tone(let f), .amTone(let f, _), .narrowband(let f, _), .toneBursts(let f, _, _, _), .cr(let f, _, _, _, _): f
        case .amNoise(let f, _): f
        default: 0
        }
        let control = VoiceControl(levelDb: levelDb, freq: 0, capDb: SafetyLimits.absoluteMaxDbfs)
        let renderer = VoiceRenderer(voice: SynthVoice(recipe: recipe, sampleRate: fs, control: control), ear: ear)
        let format = AVAudioFormat(standardFormatWithSampleRate: fs, channels: 2)!
        let node = Self.makeSourceNode(format: format, renderer: renderer)
        let handle = VoiceHandle(control: control, recipe: recipe, purpose: purpose, frequencyHint: hint, node: node, extraCap: extraCapDb, owner: self)
        handle.applyCap(SafetyLimits.capDbfs(purpose: purpose, estimator: estimator, freq: hint))
        engine.attach(node)
        engine.connect(node, to: submix, format: format)
        voices.append(handle)
        activeVoiceCount = voices.count
        startTicking()
        return handle
    }

    /// Plays a notched music buffer (mono samples at `sampleRate`) in a loop.
    public func playMusic(samples: [Float], sampleRate: Double, ear: Ear, levelDb: Double) throws -> PlayerVoice {
        try ensureRunning()
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw NSError(domain: "TinnitusAudio", code: 1)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let (gl, gr) = ear.gains
        let l = buffer.floatChannelData![0], r = buffer.floatChannelData![1]
        for i in samples.indices {
            l[i] = samples[i] * gl
            r[i] = samples[i] * gr
        }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: submix, format: format)
        let voice = PlayerVoice(player: player, levelDb: levelDb, owner: self)
        voice.applyCap(SafetyLimits.capDbfs(purpose: .sound, estimator: estimator, freq: 0))
        player.volume = 0
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
        voice.fadeIn()
        voices.append(voice)
        activeVoiceCount = voices.count
        startTicking()
        return voice
    }

    /// Soft bell used as a cue in guided exercises.
    public func chime(levelDb: Double = -28) {
        play(.chime, ear: .both, levelDb: levelDb, purpose: .cue)
    }

    public func stopAll(fadeMs: Double = 60) {
        for v in voices { v.stop(fadeMs: fadeMs) }
    }

    /// Re-evaluates the safety caps (after volume, route or calibration changes).
    public func refreshCaps() {
        let est = estimator
        for v in voices {
            v.applyCap(SafetyLimits.capDbfs(purpose: v.purpose, estimator: est, freq: v.frequencyHint))
        }
    }

    /// Detaches finished voices.
    func reap() {
        var keep: [any SoundVoice] = []
        for v in voices {
            if v.isFinished {
                if let h = v as? VoiceHandle { engine.detach(h.node) }
                if let p = v as? PlayerVoice { engine.detach(p.player) }
            } else {
                keep.append(v)
            }
        }
        voices = keep
        activeVoiceCount = voices.count
    }

    /// 4 Hz housekeeping: reap finished voices; once per second add to the dose counter.
    private func startTicking() {
        guard tickTask == nil, !manual else { return }
        tickTask = Task { @MainActor [weak self] in
            var n = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                self.reap()
                n += 1
                if n % 4 == 0 { self.accumulateDose(seconds: 1) }
                if self.voices.isEmpty {
                    self.tickTask = nil
                    return
                }
            }
        }
    }

    /// Energy sum of all sound voices, estimated in dB SPL.
    public var estimatedSPL: Double? {
        let est = estimator
        let levels = voices.filter { $0.purpose != .cue && !$0.isFinished }.map { v -> Double in
            let lvl = (v as? VoiceHandle)?.effectiveLevelDb ?? v.levelDb
            return est.spl(dbfs: lvl, at: v.frequencyHint > 0 ? v.frequencyHint : 1000)
        }
        guard !levels.isEmpty else { return nil }
        return 10 * log10(levels.reduce(0) { $0 + pow(10, $1 / 10) })
    }

    private func accumulateDose(seconds: Double) {
        guard let spl = estimatedSPL else { return }
        dose.add(spl: spl, seconds: seconds)
        doseToday = dose.today()
        if doseToday >= DoseMeter.warnAt && !doseWarned {
            doseWarned = true
            onDoseWarning?(doseToday)
        }
    }

    // MARK: Analyser

    @ObservationIgnored private var analyserUsers = 0

    /// Several views can show the spectrum at once; the tap runs while at least one needs it.
    public func retainAnalyser() {
        analyserUsers += 1
        analyserEnabled = true
    }

    public func releaseAnalyser() {
        analyserUsers = max(0, analyserUsers - 1)
        if analyserUsers == 0 { analyserEnabled = false }
    }

    public var analyserEnabled = false {
        didSet {
            guard analyserEnabled != oldValue else { return }
            if analyserEnabled && !tapInstalled {
                Self.installAnalyserTap(on: engine.mainMixerNode, analyzer: analyzer, sampleRate: sampleRate)
                tapInstalled = true
            } else if !analyserEnabled && tapInstalled {
                engine.mainMixerNode.removeTap(onBus: 0)
                tapInstalled = false
            }
        }
    }

    // MARK: Offline rendering (tests)

    /// Renders `frames` stereo frames in manual rendering mode.
    public func renderOffline(frames: Int) throws -> (left: [Float], right: [Float]) {
        precondition(manual, "renderOffline requires manual rendering mode")
        if !engine.isRunning { try engine.start() }
        let fmt = engine.manualRenderingFormat
        var left: [Float] = [], right: [Float] = []
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: engine.manualRenderingMaximumFrameCount)!
        var remaining = frames
        while remaining > 0 {
            let n = min(Int(buf.frameCapacity), remaining)
            let status = try engine.renderOffline(AVAudioFrameCount(n), to: buf)
            guard status == .success else { break }
            let l = buf.floatChannelData![0], r = buf.floatChannelData![1]
            left.append(contentsOf: UnsafeBufferPointer(start: l, count: Int(buf.frameLength)))
            right.append(contentsOf: UnsafeBufferPointer(start: r, count: Int(buf.frameLength)))
            remaining -= Int(buf.frameLength)
        }
        reap()
        return (left, right)
    }

    // MARK: Real-time callbacks
    //
    // Closures created inside this @MainActor class inherit main-actor isolation, and Swift 6 checks
    // that at runtime. Callbacks that run on audio or KVO threads are therefore built in nonisolated
    // static helpers.

    nonisolated static func makeSourceNode(format: AVAudioFormat, renderer: VoiceRenderer) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, abl -> OSStatus in
            renderer.render(frames: Int(frameCount), into: UnsafeMutableAudioBufferListPointer(abl))
            return noErr
        }
    }

    nonisolated static func installAnalyserTap(on node: AVAudioMixerNode, analyzer: SpectrumAnalyzer, sampleRate: Double) {
        node.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in
            analyzer.process(buffer, sampleRate: sampleRate)
        }
    }

    #if os(iOS)
    nonisolated static func observeVolume(_ s: AVAudioSession, onChange: @escaping @MainActor @Sendable (Double) -> Void) -> NSKeyValueObservation {
        s.observe(\.outputVolume, options: [.new]) { _, change in
            guard let v = change.newValue else { return }
            Task { @MainActor in onChange(Double(v)) }
        }
    }
    #endif

    // MARK: Session observers

    #if os(iOS)
    private func observeSession() {
        let nc = NotificationCenter.default
        let s = AVAudioSession.sharedInstance()
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: s, queue: .main) { [weak self] n in
            let type = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let opts = (n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            MainActor.assumeIsolated {
                guard let self, let type else { return }
                if type == .began {
                    self.onInterruption?(true, false)
                } else {
                    try? AVAudioSession.sharedInstance().setActive(true)
                    if !self.engine.isRunning { try? self.engine.start() }
                    self.onInterruption?(false, opts.contains(.shouldResume))
                }
            }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: s, queue: .main) { [weak self] n in
            let reason = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            MainActor.assumeIsolated {
                guard let self else { return }
                self.route = AudioRouteInfo.current()
                self.refreshCaps()
                if reason == .oldDeviceUnavailable { self.onRouteLost?() }
            }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: s, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.voices.removeAll()
                self.activeVoiceCount = 0
                self.configureSession()
            }
        })
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.voices.isEmpty else { return }
                try? self.engine.start()
            }
        })
        volumeObservation = Self.observeVolume(s) { [weak self] v in
            // after a system volume change during a session: recompute and lower if needed
            self?.systemVolume = v
            self?.refreshCaps()
        }
    }
    #endif
}

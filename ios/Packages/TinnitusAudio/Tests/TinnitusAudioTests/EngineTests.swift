import AVFoundation
import Foundation
import Testing
import TinnitusCore
@testable import TinnitusAudio

@Suite("Audio engine (offline rendering)")
@MainActor
struct EngineTests {
    func rms(_ x: ArraySlice<Float>) -> Double { OfflineRender.rms(x) }

    @Test("Ear routing: left-only voice is silent on the right")
    func earRouting() throws {
        let e = AudioEngine(manualRendering: true)
        e.masterVolume = 1
        e.play(.tone(freq: 1000), ear: .left, levelDb: -20, purpose: .cue)
        let (l, r) = try e.renderOffline(frames: 24000)
        #expect(rms(l[4800...]) > 0.05)
        #expect(rms(r[4800...]) < 1e-6)
    }

    @Test("Graph applies the notch: tone at f_T through notched noise path is attenuated")
    func notchThroughGraph() throws {
        let e = AudioEngine(manualRendering: true)
        e.masterVolume = 1
        e.play(.notchedNoise(.white, center: 6000, widthOctaves: 1), ear: .both, levelDb: -12, purpose: .cue)
        let (l, _) = try e.renderOffline(frames: 96000)
        var bpF = BiquadChain([BiquadCoefficients(.bandpass, frequency: 6000, q: 8, sampleRate: 48000), BiquadCoefficients(.bandpass, frequency: 6000, q: 8, sampleRate: 48000)])
        var bpLow = BiquadChain([BiquadCoefficients(.bandpass, frequency: 1500, q: 8, sampleRate: 48000), BiquadCoefficients(.bandpass, frequency: 1500, q: 8, sampleRate: 48000)])
        let a = l.map { Float(bpF.process(Double($0))) }
        let b = l.map { Float(bpLow.process(Double($0))) }
        let hole = Level.gainToDb(rms(a[9600...]) / rms(b[9600...]))
        #expect(hole < -12, "hole \(hole) dB")
    }

    @Test("Hard cap: nothing above −6 dBFS even if a voice asks for 0 dBFS")
    func hardCap() throws {
        let e = AudioEngine(manualRendering: true)
        e.masterVolume = 1
        e.play(.tone(freq: 1000), ear: .both, levelDb: 0, purpose: .cue)
        let (l, _) = try e.renderOffline(frames: 24000)
        let peak = l[4800...].map { abs($0) }.max() ?? 0
        #expect(peak <= Float(Level.dbToGain(-6)) * 1.02)
    }

    @Test("Stopped voices are detached after their fade")
    func reap() throws {
        let e = AudioEngine(manualRendering: true)
        let v = e.play(.noise(.pink), ear: .both, levelDb: -30, purpose: .sound)
        _ = try e.renderOffline(frames: 4800)
        v.stop(fadeMs: 20)
        _ = try e.renderOffline(frames: 4800)
        #expect(e.activeVoiceCount == 0)
    }

    @Test("Bursts finish by themselves and get reaped")
    func bursts() throws {
        let e = AudioEngine(manualRendering: true)
        e.play(.toneBursts(freq: 2000), ear: .right, levelDb: -40, purpose: .measurement)
        _ = try e.renderOffline(frames: 48000 * 2)
        #expect(e.activeVoiceCount == 0)
    }
}

@Suite("Calibration & safety")
struct CalibrationTests {
    @Test func routeClassification() {
        #expect(AudioRouteInfo.classify(portType: "BluetoothA2DPOutput", name: "Tobias’ AirPods Pro") == .airPodsPro2)
        #expect(AudioRouteInfo.classify(portType: "BluetoothA2DPOutput", name: "AirPods Max") == .airPodsMax)
        #expect(AudioRouteInfo.classify(portType: "BluetoothA2DPOutput", name: "WH-1000XM5") == .bluetooth)
        #expect(AudioRouteInfo.classify(portType: "Speaker", name: "Lautsprecher") == .speaker)
        #expect(AudioRouteInfo.classify(portType: "Headphones", name: "Kopfhörer") == .wired)
    }

    @Test("Caps keep the estimated level at or below 85/80 dB SPL")
    func caps() {
        for kind in DeviceKind.allCases {
            for vol in [0.25, 0.5, 1.0] {
                let est = LevelEstimator(profile: .profile(for: kind), masterVolume: 1, systemVolume: vol)
                let s = SafetyLimits.capDbfs(purpose: .sound, estimator: est, freq: 4000)
                let m = SafetyLimits.capDbfs(purpose: .measurement, estimator: est, freq: 4000)
                #expect(est.spl(dbfs: s, at: 4000) <= 85.0001)
                #expect(est.spl(dbfs: m, at: 4000) <= 80.0001)
                #expect(s <= -6 && m <= -6)
            }
        }
    }

    @Test func estimatorRoundTrip() {
        let est = LevelEstimator(profile: .profile(for: .airPodsPro2), masterVolume: 0.5, systemVolume: 0.6, userOffset: -2)
        let spl = est.spl(dbfs: -30, at: 6000)
        #expect(abs(est.dbfs(forSPL: spl, at: 6000) + 30) < 1e-9)
        #expect(SafetyLimits.riCap(mmlDb: -40, loudnessDb: -30) == -25)
        #expect(!SafetyLimits.allowsMeasurement(.speaker))
        #expect(SafetyLimits.maxDurationS(spl: 78) == 300)
    }

    @Test func doseMeter() {
        let d = UserDefaults(suiteName: "test.dose.\(UUID().uuidString)")!
        let m = DoseMeter(defaults: d)
        m.add(spl: 80, seconds: 40.0 / 7 * 3600 / 2)
        #expect(abs(m.today() - 0.5) < 1e-9)
    }
}

@Suite("Real-time thread safety")
struct RealtimeTests {
    /// The source node's render block must not be main-actor isolated: the audio thread calls it.
    /// Rendering happens on a detached (non-main) task here, like on the real audio thread.
    @Test func renderBlockRunsOffMainThread() async throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let control = VoiceControl(levelDb: -20)
        let renderer = VoiceRenderer(voice: SynthVoice(recipe: .tone(freq: 1000), sampleRate: 48000, control: control), ear: .left)
        let rms: Double = await Task.detached { () -> Double in
            let engine = AVAudioEngine()
            try? engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
            let node = AudioEngine.makeSourceNode(format: format, renderer: renderer)
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            guard (try? engine.start()) != nil else { return -1 }
            let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
            guard (try? engine.renderOffline(4096, to: buf)) == .success else { return -2 }
            let l = UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength))
            return OfflineRender.rms(ArraySlice(Array(l)))
        }.value
        #expect(rms > 0.01, "rms \(rms)")
    }
}

@Suite("Spectrum analyser")
struct AnalyserTests {
    @Test("Peak bin follows a tone; low sample rates don't crash", arguments: [16000.0, 44100.0, 48000.0])
    func peak(rate: Double) {
        let a = SpectrumAnalyzer()
        let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 4096)!
        buf.frameLength = 4096
        let tone = OfflineRender.render(.tone(freq: 3000), seconds: 4096 / rate + 0.05, sampleRate: rate)
        for c in 0..<2 { for i in 0..<4096 { buf.floatChannelData![c][i] = tone[i + Int(0.03 * rate)] } }
        for _ in 0..<12 { a.process(buf, sampleRate: 48000) }
        let bins = a.bins()
        let maxIdx = bins.indices.max { bins[$0] < bins[$1] }!
        let f = SpectrumAnalyzer.frequency(ofBin: maxIdx)
        #expect(abs(log2(f / 3000)) < 0.15, "peak at \(f) Hz")
    }
}
